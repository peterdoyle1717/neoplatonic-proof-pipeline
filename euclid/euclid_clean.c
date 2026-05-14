#define _POSIX_C_SOURCE 200809L

/* euclid_clean.c -- neoplatonic Euclidean solver + realizer in one file.
 *
 * Pipeline: netcode -> topology -> wish init -> LM-with-dent-gate at
 * alpha = pi/3 -> realize from face 0 in standard gauge -> OBJ with %.17f.
 *
 * Build:  make
 * Usage:  euclid_clean "a,b,c;d,e,f;..."  > out.obj
 *
 * Conventions:
 *   - All edges are LM variables; all vertices contribute residuals.
 *     System size: 3*NV residuals, NE = 3*NV - 6 variables.
 *   - Dent gate: vertex_turn(v) = sum of bends in flower(v) >= 0
 *     for every vertex on every accepted LM step.
 *   - Realize uses bends as supplied; no post-LM base-bend recovery.
 *   - OBJ coordinates are written as %.17f -- fixed-point, no
 *     scientific notation, full double precision retained for
 *     magnitudes of order 1.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* LAPACK general-LU solver (column-major). */
extern void dgesv_(int *n, int *nrhs, double *a, int *lda, int *ipiv,
                   double *b, int *ldb, int *info);

/* ============================================================
 *   Topology -- global state, sized for v <= MAXV.
 * ============================================================ */

#define MAXV 200
#define MAXF (2 * MAXV + 4)
#define MAXE (3 * MAXV + 6)
#define MAXDEG 16

static int NV, NF, NE;
static int FACES[MAXF][3];                 /* (a, b, c) per face, 1-indexed verts */
static int EDGE_A[MAXE], EDGE_B[MAXE];     /* edge endpoints, EDGE_A < EDGE_B */
static int EDGE_IDX[MAXV + 1][MAXV + 1];   /* (lo, hi) -> edge index, -1 if none */
static int DIR_FACE[MAXV + 1][MAXV + 1];   /* directed (u, v) -> face id, -1 if none */
static int VERT_DEG[MAXV + 1];
static int FLOWER_LEN[MAXV + 1];
static int FLOWER_E[MAXV + 1][MAXDEG];     /* v-incident edges, flower order */

static int parse_netcode(const char *s)
{
    NV = 0;
    NF = 0;
    const char *p = s;

    while (*p) {
        int a, b, c;
        if (sscanf(p, "%d,%d,%d", &a, &b, &c) != 3) return -1;
        if (NF >= MAXF || a < 1 || a > MAXV || b < 1 || b > MAXV || c < 1 || c > MAXV)
            return -1;

        FACES[NF][0] = a;
        FACES[NF][1] = b;
        FACES[NF][2] = c;
        NF++;
        if (a > NV) NV = a;
        if (b > NV) NV = b;
        if (c > NV) NV = c;

        while (*p && *p != ';') p++;
        if (*p == ';') p++;
    }
    return NF;
}

static int build_topology(void)
{
    NE = 0;
    for (int i = 0; i <= MAXV; i++) {
        VERT_DEG[i] = 0;
        for (int j = 0; j <= MAXV; j++) {
            EDGE_IDX[i][j] = -1;
            DIR_FACE[i][j] = -1;
        }
    }

    for (int fi = 0; fi < NF; fi++) {
        int v[3] = { FACES[fi][0], FACES[fi][1], FACES[fi][2] };
        for (int k = 0; k < 3; k++) {
            int u = v[k], w = v[(k + 1) % 3];
            DIR_FACE[u][w] = fi;
            int lo = u < w ? u : w;
            int hi = u < w ? w : u;
            if (EDGE_IDX[lo][hi] < 0) {
                if (NE >= MAXE) return -1;
                EDGE_IDX[lo][hi] = NE;
                EDGE_A[NE] = lo;
                EDGE_B[NE] = hi;
                VERT_DEG[lo]++;
                VERT_DEG[hi]++;
                NE++;
            }
        }
    }

    for (int v = 1; v <= NV; v++) {
        int start = -1;
        for (int fi = 0; fi < NF; fi++) {
            if (FACES[fi][0] == v || FACES[fi][1] == v || FACES[fi][2] == v) {
                start = fi;
                break;
            }
        }
        if (start < 0) return -1;

        int cur = start;
        int k = 0;
        do {
            int a = FACES[cur][0], b = FACES[cur][1], c = FACES[cur][2];
            int third = (v == a) ? c : (v == b) ? a : b;
            int lo = v < third ? v : third;
            int hi = v < third ? third : v;
            if (k >= MAXDEG) return -1;
            FLOWER_E[v][k++] = EDGE_IDX[lo][hi];
            cur = DIR_FACE[v][third];
        } while (cur != start);
        FLOWER_LEN[v] = k;
    }
    return 0;
}

/* ============================================================
 *   Wish init.
 *
 *   For each edge e = (i, j), set
 *       g_e = 1/d_i + 1/d_j         (d_v = vertex degree)
 *       c_v = 1
 *   Solve  (B B^T) lambda = B g - 2 c   (B is V x E incidence)
 *   then   x_e = (g_e - sum_{v in e} lambda_v) / 2
 *   then   bend_e = 2 pi x_e.
 *
 *   The reduced V x V system is solved with dgesv.
 * ============================================================ */

static int wish_init(double *bend)
{
    static double BBt[MAXV * MAXV];
    static double rhs[MAXV];
    static double g[MAXE];
    int ipiv[MAXV];

    for (int e = 0; e < NE; e++) {
        int i = EDGE_A[e], j = EDGE_B[e];
        g[e] = 1.0 / (double)VERT_DEG[i] + 1.0 / (double)VERT_DEG[j];
    }

    /* (B B^T)_{ii} = deg(i);  (B B^T)_{ij} = 1 if edge (i, j) exists. */
    for (int i = 1; i <= NV; i++)
        for (int j = 1; j <= NV; j++) {
            double v = 0.0;
            if (i == j)
                v = (double)VERT_DEG[i];
            else {
                int lo = i < j ? i : j, hi = i < j ? j : i;
                if (EDGE_IDX[lo][hi] >= 0) v = 1.0;
            }
            BBt[(i - 1) + (j - 1) * NV] = v;
        }

    for (int i = 0; i < NV; i++) rhs[i] = -2.0;
    for (int e = 0; e < NE; e++) {
        rhs[EDGE_A[e] - 1] += g[e];
        rhs[EDGE_B[e] - 1] += g[e];
    }

    int n = NV, nrhs = 1, info;
    dgesv_(&n, &nrhs, BBt, &n, ipiv, rhs, &n, &info);
    if (info != 0) {
        fprintf(stderr, "wish_init: dgesv info=%d\n", info);
        return -1;
    }

    for (int e = 0; e < NE; e++) {
        double x = (g[e] - rhs[EDGE_A[e] - 1] - rhs[EDGE_B[e] - 1]) * 0.5;
        bend[e] = 2.0 * M_PI * x;
    }
    return 0;
}

/* ============================================================
 *   Quaternion holonomy residual and analytic Jacobian.
 *
 *   q_step(alpha, beta) = q_z(alpha) * q_x(-beta)
 *   Quat layout: (w, x, y, z).
 *   Residual at v: vec( prod_{e in flower(v)} q_step(alpha, bend_e) ).
 * ============================================================ */

typedef double Quat[4];

static void q_mul(const Quat a, const Quat b, Quat r)
{
    double w = a[0]*b[0] - a[1]*b[1] - a[2]*b[2] - a[3]*b[3];
    double x = a[0]*b[1] + a[1]*b[0] + a[2]*b[3] - a[3]*b[2];
    double y = a[0]*b[2] - a[1]*b[3] + a[2]*b[0] + a[3]*b[1];
    double z = a[0]*b[3] + a[1]*b[2] - a[2]*b[1] + a[3]*b[0];
    r[0] = w; r[1] = x; r[2] = y; r[3] = z;
}

static void q_step(double alpha, double beta, Quat q)
{
    double ca = cos(0.5 * alpha), sa = sin(0.5 * alpha);
    double cb = cos(0.5 * beta),  sb = sin(0.5 * beta);
    q[0] =  ca * cb;
    q[1] = -ca * sb;
    q[2] = -sa * sb;
    q[3] =  sa * cb;
}

static void q_step_dbeta(double alpha, double beta, Quat q)
{
    double ca = cos(0.5 * alpha), sa = sin(0.5 * alpha);
    double cb = cos(0.5 * beta),  sb = sin(0.5 * beta);
    q[0] = -0.5 * ca * sb;
    q[1] = -0.5 * ca * cb;
    q[2] = -0.5 * sa * cb;
    q[3] = -0.5 * sa * sb;
}

static void residual(double alpha, const double *bend, double *r)
{
    for (int v = 1; v <= NV; v++) {
        Quat Q = { 1.0, 0.0, 0.0, 0.0 };
        int k = FLOWER_LEN[v];
        for (int t = 0; t < k; t++) {
            Quat step, tmp;
            q_step(alpha, bend[FLOWER_E[v][t]], step);
            q_mul(Q, step, tmp);
            Q[0] = tmp[0]; Q[1] = tmp[1]; Q[2] = tmp[2]; Q[3] = tmp[3];
        }
        r[3 * (v - 1) + 0] = Q[1];
        r[3 * (v - 1) + 1] = Q[2];
        r[3 * (v - 1) + 2] = Q[3];
    }
}

/* Dense Jacobian, column-major: J[i + e*rows] = d r_i / d bend_e.
   rows = 3 * NV, columns = NE. */
static void jacobian(double alpha, const double *bend, double *J)
{
    int rows = 3 * NV;
    for (int i = 0; i < rows * NE; i++) J[i] = 0.0;

    Quat qs[MAXDEG], dqs[MAXDEG];
    Quat P[MAXDEG + 1], S[MAXDEG + 1];

    for (int v = 1; v <= NV; v++) {
        int k = FLOWER_LEN[v];
        for (int t = 0; t < k; t++) {
            q_step      (alpha, bend[FLOWER_E[v][t]], qs[t]);
            q_step_dbeta(alpha, bend[FLOWER_E[v][t]], dqs[t]);
        }
        P[0][0] = 1.0; P[0][1] = P[0][2] = P[0][3] = 0.0;
        for (int t = 0; t < k; t++) q_mul(P[t], qs[t], P[t + 1]);
        S[k][0] = 1.0; S[k][1] = S[k][2] = S[k][3] = 0.0;
        for (int t = k - 1; t >= 0; t--) q_mul(qs[t], S[t + 1], S[t]);

        int row = 3 * (v - 1);
        for (int t = 0; t < k; t++) {
            Quat tmp, dQ;
            q_mul(P[t], dqs[t], tmp);
            q_mul(tmp, S[t + 1], dQ);
            int e = FLOWER_E[v][t];
            J[(row + 0) + e * rows] += dQ[1];
            J[(row + 1) + e * rows] += dQ[2];
            J[(row + 2) + e * rows] += dQ[3];
        }
    }
}

/* ============================================================
 *   Dent gate.
 * ============================================================ */

static double vertex_turn(int v, const double *bend)
{
    double s = 0.0;
    int k = FLOWER_LEN[v];
    for (int t = 0; t < k; t++) s += bend[FLOWER_E[v][t]];
    return s;
}

static int has_dent(const double *bend)
{
    for (int v = 1; v <= NV; v++) {
        if (vertex_turn(v, bend) < 0.0) return v;
    }
    return 0;
}

/* ============================================================
 *   Levenberg-Marquardt with dent gate.
 *
 *   Solve F(bend) = 0 (overdetermined: 3V residuals, NE variables).
 *   Step:  delta = -(J^T J + lambda diag(J^T J))^{-1} J^T r.
 *   Accept iff ||r_trial|| < ||r|| AND has_dent(bend_trial) == 0.
 *   On accept: lambda *= 0.3, clipped >= 1e-30.
 *   On reject: lambda *= 10, fail if > 1e12.
 *   Exit on ||r|| <= tol or after maxiter outer iterations.
 * ============================================================ */

static double r_buf[3 * MAXV];
static double rt_buf[3 * MAXV];
static double J_buf[3 * MAXV * MAXE];
static double A_buf[MAXE * MAXE];
static double M_buf[MAXE * MAXE];
static double g_buf[MAXE], delta_buf[MAXE], D_buf[MAXE];
static double bend_trial[MAXE];

static int lm_solve(double alpha, double *bend, double tol, int maxiter)
{
    int rows = 3 * NV;
    int ipiv[MAXE];
    double lambda = 1.0;

    residual(alpha, bend, r_buf);
    double norm = 0.0;
    for (int i = 0; i < rows; i++) norm += r_buf[i] * r_buf[i];
    norm = sqrt(norm);

    for (int it = 0; it < maxiter; it++) {
        if (norm <= tol) return 0;

        jacobian(alpha, bend, J_buf);

        for (int p = 0; p < NE; p++) {
            for (int q = p; q < NE; q++) {
                double s = 0.0;
                for (int i = 0; i < rows; i++)
                    s += J_buf[i + p * rows] * J_buf[i + q * rows];
                A_buf[p + q * NE] = s;
                A_buf[q + p * NE] = s;
            }
        }
        for (int p = 0; p < NE; p++) {
            double s = 0.0;
            for (int i = 0; i < rows; i++) s += J_buf[i + p * rows] * r_buf[i];
            g_buf[p] = s;
            D_buf[p] = A_buf[p + p * NE];
        }

        int accepted = 0;
        for (int retry = 0; retry < 20; retry++) {
            memcpy(M_buf, A_buf, sizeof(double) * NE * NE);
            for (int p = 0; p < NE; p++) M_buf[p + p * NE] += lambda * D_buf[p];
            for (int p = 0; p < NE; p++) delta_buf[p] = -g_buf[p];
            int n = NE, nrhs = 1, info;
            dgesv_(&n, &nrhs, M_buf, &n, ipiv, delta_buf, &n, &info);
            if (info != 0) {
                lambda *= 10.0;
                if (lambda > 1e12) return -1;
                continue;
            }

            for (int e = 0; e < NE; e++) bend_trial[e] = bend[e] + delta_buf[e];
            int dent_v = has_dent(bend_trial);
            residual(alpha, bend_trial, rt_buf);
            double n_trial = 0.0;
            for (int i = 0; i < rows; i++) n_trial += rt_buf[i] * rt_buf[i];
            n_trial = sqrt(n_trial);

            if (n_trial < norm && dent_v == 0) {
                memcpy(bend, bend_trial, sizeof(double) * NE);
                memcpy(r_buf, rt_buf, sizeof(double) * rows);
                norm = n_trial;
                lambda *= 0.3;
                if (lambda < 1e-30) lambda = 1e-30;
                accepted = 1;
                break;
            }
            lambda *= 10.0;
            if (lambda > 1e12) return -1;
        }
        if (!accepted) return -1;
    }
    return (norm <= tol) ? 0 : -1;
}

/* ============================================================
 *   Realize: BFS from face 0; place each new face's third vertex
 *   via place_third using the bend at the shared edge.
 *
 *   Standard gauge:
 *     V[FACES[0][0]] = (0, 0, +0.5)
 *     V[FACES[0][1]] = (0, 0, -0.5)
 *     V[FACES[0][2]] = (sqrt(3)/2, 0, 0)
 *
 *   No post-LM base-bend recovery; bends are used as supplied.
 * ============================================================ */

static double V_OUT[MAXV + 1][3];
static int V_PLACED[MAXV + 1];

static void vec_sub(const double a[3], const double b[3], double r[3])
{ r[0] = a[0] - b[0]; r[1] = a[1] - b[1]; r[2] = a[2] - b[2]; }
static void vec_add(const double a[3], const double b[3], double r[3])
{ r[0] = a[0] + b[0]; r[1] = a[1] + b[1]; r[2] = a[2] + b[2]; }
static void vec_scale(double s, const double a[3], double r[3])
{ r[0] = s * a[0]; r[1] = s * a[1]; r[2] = s * a[2]; }
static double vec_norm(const double a[3])
{ return sqrt(a[0]*a[0] + a[1]*a[1] + a[2]*a[2]); }
static void vec_cross(const double a[3], const double b[3], double r[3])
{
    double x = a[1]*b[2] - a[2]*b[1];
    double y = a[2]*b[0] - a[0]*b[2];
    double z = a[0]*b[1] - a[1]*b[0];
    r[0] = x; r[1] = y; r[2] = z;
}

/* Place vertex c opposite p across edge (a, b) with dihedral bend theta. */
static void place_third(int a, int b, int p, double theta, int c)
{
    double m[3], e_hat[3], p_perp[3], u_hat[3], v_hat[3], c_perp[3];
    double t1[3], t2[3];
    vec_add(V_OUT[a], V_OUT[b], m);
    vec_scale(0.5, m, m);
    vec_sub(V_OUT[b], V_OUT[a], e_hat);
    vec_sub(V_OUT[p], m, p_perp);
    vec_scale(1.0 / vec_norm(p_perp), p_perp, u_hat);
    vec_cross(u_hat, e_hat, v_hat);
    vec_scale(1.0 / vec_norm(v_hat), v_hat, v_hat);
    double ct = cos(theta), st = sin(theta);
    vec_scale(-ct, u_hat, t1);
    vec_scale( st, v_hat, t2);
    vec_add(t1, t2, c_perp);
    vec_scale(sqrt(3.0) / 2.0, c_perp, t1);
    vec_add(m, t1, V_OUT[c]);
}

static int realize(const double *bend)
{
    static int queue[MAXF], placed_f[MAXF];

    for (int v = 0; v <= NV; v++) V_PLACED[v] = 0;
    for (int fi = 0; fi < NF; fi++) placed_f[fi] = 0;

    int b0 = FACES[0][0], b1 = FACES[0][1], b2 = FACES[0][2];
    V_OUT[b0][0] = 0.0;             V_OUT[b0][1] = 0.0; V_OUT[b0][2] =  0.5;
    V_OUT[b1][0] = 0.0;             V_OUT[b1][1] = 0.0; V_OUT[b1][2] = -0.5;
    V_OUT[b2][0] = sqrt(3.0) / 2.0; V_OUT[b2][1] = 0.0; V_OUT[b2][2] =  0.0;
    V_PLACED[b0] = V_PLACED[b1] = V_PLACED[b2] = 1;
    placed_f[0] = 1;

    int qh = 0, qt = 0;
    queue[qt++] = 0;
    while (qh < qt) {
        int fi = queue[qh++];
        int v[3] = { FACES[fi][0], FACES[fi][1], FACES[fi][2] };
        for (int k = 0; k < 3; k++) {
            int a = v[k], b = v[(k + 1) % 3];
            int other_fi = DIR_FACE[b][a];
            if (placed_f[other_fi]) continue;
            int oa = FACES[other_fi][0], ob = FACES[other_fi][1], oc = FACES[other_fi][2];
            int c = (oa != a && oa != b) ? oa
                  : (ob != a && ob != b) ? ob : oc;
            int p = (v[0] != a && v[0] != b) ? v[0]
                  : (v[1] != a && v[1] != b) ? v[1] : v[2];
            int lo = a < b ? a : b, hi = a < b ? b : a;
            int e = EDGE_IDX[lo][hi];
            place_third(a, b, p, bend[e], c);
            V_PLACED[c] = 1;
            placed_f[other_fi] = 1;
            queue[qt++] = other_fi;
        }
    }
    return 0;
}

static int write_obj(FILE *fp)
{
    for (int v = 1; v <= NV; v++) {
        if (fprintf(fp, "v %.17f %.17f %.17f\n",
                    V_OUT[v][0], V_OUT[v][1], V_OUT[v][2]) < 0)
            return -1;
    }
    for (int fi = 0; fi < NF; fi++) {
        if (fprintf(fp, "f %d %d %d\n",
                    FACES[fi][0], FACES[fi][1], FACES[fi][2]) < 0)
            return -1;
    }
    return ferror(fp) ? -1 : 0;
}

/* ============================================================
 *   One-item driver and batch helpers.
 * ============================================================ */

static void set_errmsg(char *errmsg, size_t errmsgsize, const char *msg)
{
    if (errmsgsize > 0) {
        snprintf(errmsg, errmsgsize, "%s", msg);
    }
}

static int solve_one_netcode(const char *netcode, FILE *objout,
                             char *errmsg, size_t errmsgsize)
{
    static double bend[MAXE];

    if (errmsgsize > 0) errmsg[0] = '\0';

    if (parse_netcode(netcode) <= 0) {
        set_errmsg(errmsg, errmsgsize, "parse failed");
        return 1;
    }
    if (build_topology() < 0) {
        set_errmsg(errmsg, errmsgsize, "build_topology failed");
        return 1;
    }
    if (wish_init(bend) < 0) {
        set_errmsg(errmsg, errmsgsize, "wish_init failed");
        return 1;
    }

    double alpha = M_PI / 3.0;
    if (lm_solve(alpha, bend, 1e-12, 200) < 0) {
        set_errmsg(errmsg, errmsgsize, "LM did not converge");
        return 1;
    }
    if (realize(bend) < 0) {
        set_errmsg(errmsg, errmsgsize, "realize failed");
        return 1;
    }
    if (write_obj(objout) < 0) {
        set_errmsg(errmsg, errmsgsize, "OBJ write failed");
        return 1;
    }

    return 0;
}

static void chomp(char *s)
{
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == '\n' || s[n - 1] == '\r')) {
        s[--n] = '\0';
    }
}

static uint64_t fnv1a64(const char *s)
{
    uint64_t h = UINT64_C(1469598103934665603);
    while (*s) {
        h ^= (unsigned char)*s++;
        h *= UINT64_C(1099511628211);
    }
    return h;
}

static int ensure_directory_exists(const char *path)
{
    struct stat st;
    if (stat(path, &st) == 0) {
        return S_ISDIR(st.st_mode) ? 0 : -1;
    }
    if (errno == ENOENT) {
        if (mkdir(path, 0777) == 0) return 0;
    }
    return -1;
}

static int make_output_paths(const char *outdir, long index, uint64_t hash,
                             char *finalpath, size_t finalsize,
                             char *tmppath, size_t tmpsize)
{
    int n1 = snprintf(finalpath, finalsize, "%s/n%08ld_%016llx.obj",
                      outdir, index, (unsigned long long)hash);
    int n2 = snprintf(tmppath, tmpsize, "%s/.tmp_n%08ld_%016llx_%ld.obj",
                      outdir, index, (unsigned long long)hash, (long)getpid());
    if (n1 < 0 || n2 < 0) return -1;
    if ((size_t)n1 >= finalsize || (size_t)n2 >= tmpsize) return -1;
    return 0;
}

static int run_batch(const char *outdir)
{
    if (ensure_directory_exists(outdir) < 0) {
        fprintf(stderr, "cannot use output directory %s: %s\n", outdir, strerror(errno));
        return 2;
    }

    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    long index = 0;
    int failures = 0;

    while ((len = getline(&line, &cap, stdin)) != -1) {
        (void)len;
        chomp(line);
        if (line[0] == '\0') continue;

        uint64_t hash = fnv1a64(line);
        char finalpath[4096], tmppath[4096], errmsg[512];
        errmsg[0] = '\0';

        if (make_output_paths(outdir, index, hash, finalpath, sizeof(finalpath),
                              tmppath, sizeof(tmppath)) < 0) {
            snprintf(errmsg, sizeof(errmsg), "output path too long");
            fprintf(stdout, "%ld\tfail\t%s\t\t%s\n", index, line, errmsg);
            failures++;
            index++;
            continue;
        }

        FILE *fp = fopen(tmppath, "w");
        if (!fp) {
            snprintf(errmsg, sizeof(errmsg), "could not open temp OBJ: %s", strerror(errno));
            fprintf(stdout, "%ld\tfail\t%s\t\t%s\n", index, line, errmsg);
            failures++;
            index++;
            continue;
        }

        int rc = solve_one_netcode(line, fp, errmsg, sizeof(errmsg));
        int close_failed = 0;
        if (fflush(fp) != 0) close_failed = 1;
        if (fclose(fp) != 0) close_failed = 1;

        if (rc == 0 && close_failed) {
            snprintf(errmsg, sizeof(errmsg), "could not close temp OBJ cleanly: %s", strerror(errno));
            rc = 1;
        }

        if (rc == 0) {
            if (rename(tmppath, finalpath) != 0) {
                snprintf(errmsg, sizeof(errmsg), "rename failed: %s", strerror(errno));
                remove(tmppath);
                fprintf(stdout, "%ld\tfail\t%s\t\t%s\n", index, line, errmsg);
                failures++;
            } else {
                fprintf(stdout, "%ld\tok\t%s\t%s\t\n", index, line, finalpath);
            }
        } else {
            remove(tmppath);
            if (errmsg[0] == '\0') snprintf(errmsg, sizeof(errmsg), "solver failed");
            fprintf(stderr, "[%ld] %s\n", index, errmsg);
            fprintf(stdout, "%ld\tfail\t%s\t\t%s\n", index, line, errmsg);
            failures++;
        }

        index++;
    }

    free(line);
    if (ferror(stdin)) {
        fprintf(stderr, "error while reading stdin\n");
        return 2;
    }
    return failures ? 1 : 0;
}

static void usage(const char *prog)
{
    fprintf(stderr, "usage:\n");
    fprintf(stderr, "  %s NETCODE\n", prog);
    fprintf(stderr, "  %s --batch --outdir DIR < netcodes.txt\n", prog);
}

/* ============================================================
 *   main
 * ============================================================ */

int main(int argc, char **argv)
{
    if (argc == 2 && strcmp(argv[1], "--batch") != 0) {
        char errmsg[512];
        int rc = solve_one_netcode(argv[1], stdout, errmsg, sizeof(errmsg));
        if (rc != 0) {
            fprintf(stderr, "%s\n", errmsg[0] ? errmsg : "solver failed");
            return 1;
        }
        return 0;
    }

    if (argc == 4 && strcmp(argv[1], "--batch") == 0 && strcmp(argv[2], "--outdir") == 0) {
        return run_batch(argv[3]);
    }

    usage(argv[0]);
    return 2;
}
