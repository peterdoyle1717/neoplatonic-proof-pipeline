#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAXV 200
#define MAXF (2 * MAXV + 4)

typedef struct { int a, b, c; } Face;
typedef struct { double x, y, z; } Vec3;

static void *xcalloc(size_t n, size_t size)
{
    void *p = calloc(n, size);
    if (!p) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    return p;
}

static void *xrealloc(void *p, size_t size)
{
    void *q = realloc(p, size);
    if (!q) {
        fprintf(stderr, "out of memory\n");
        exit(2);
    }
    return q;
}

static void chomp(char *s)
{
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == '\n' || s[n - 1] == '\r')) s[--n] = '\0';
}

static void setmsg(char *msg, size_t msglen, const char *text)
{
    if (msglen > 0) snprintf(msg, msglen, "%s", text);
}

static bool parse_int_token(const char **pp, long *out)
{
    const char *p = *pp;
    while (isspace((unsigned char)*p)) p++;
    if (!isdigit((unsigned char)*p)) return false;
    errno = 0;
    char *end = NULL;
    long v = strtol(p, &end, 10);
    if (errno || end == p) return false;
    *out = v;
    *pp = end;
    return true;
}

static bool parse_netcode(const char *s, Face **facesout, int *nvout, int *nfout, char *msg, size_t msglen)
{
    Face *faces = (Face *)xcalloc((size_t)MAXF, sizeof(Face));
    int nv = 0;
    int nf = 0;
    const char *p = s;

    while (1) {
        while (isspace((unsigned char)*p)) p++;
        if (*p == '\0') break;

        long a, b, c;
        if (!parse_int_token(&p, &a) || *p++ != ',' ||
            !parse_int_token(&p, &b) || *p++ != ',' ||
            !parse_int_token(&p, &c)) {
            setmsg(msg, msglen, "bad netcode syntax");
            free(faces);
            return false;
        }
        if (a < 1 || a > MAXV || b < 1 || b > MAXV || c < 1 || c > MAXV) {
            setmsg(msg, msglen, "vertex index outside supported range");
            free(faces);
            return false;
        }
        if (a == b || a == c || b == c) {
            setmsg(msg, msglen, "degenerate face");
            free(faces);
            return false;
        }
        if (nf >= MAXF) {
            setmsg(msg, msglen, "too many faces for compiled capacity");
            free(faces);
            return false;
        }

        faces[nf++] = (Face){(int)a - 1, (int)b - 1, (int)c - 1};
        if (a > nv) nv = (int)a;
        if (b > nv) nv = (int)b;
        if (c > nv) nv = (int)c;

        while (isspace((unsigned char)*p)) p++;
        if (*p == ';') {
            p++;
            continue;
        }
        if (*p == '\0') break;
        setmsg(msg, msglen, "expected semicolon after face");
        free(faces);
        return false;
    }

    if (nf == 0) {
        setmsg(msg, msglen, "empty netcode");
        free(faces);
        return false;
    }

    *facesout = faces;
    *nvout = nv;
    *nfout = nf;
    return true;
}

static bool read_obj(const char *path, Vec3 **vertsout, int *nvout, Face **facesout, int *nfout, char *msg, size_t msglen)
{
    FILE *fp = fopen(path, "r");
    if (!fp) {
        snprintf(msg, msglen, "%s: %s", path, strerror(errno));
        return false;
    }

    int vc = 0, vcap = 64;
    int fc = 0, fcap = 64;
    Vec3 *verts = (Vec3 *)xcalloc((size_t)vcap, sizeof(Vec3));
    Face *faces = (Face *)xcalloc((size_t)fcap, sizeof(Face));
    char line[4096];

    while (fgets(line, sizeof(line), fp)) {
        char *s = line;
        while (isspace((unsigned char)*s)) s++;
        if (*s == '\0' || *s == '#') continue;

        if (s[0] == 'v' && isspace((unsigned char)s[1])) {
            char *p = s + 1;
            errno = 0;
            double x = strtod(p, &p);
            double y = strtod(p, &p);
            double z = strtod(p, &p);
            if (errno || !isfinite(x) || !isfinite(y) || !isfinite(z)) {
                setmsg(msg, msglen, "bad OBJ vertex");
                goto fail;
            }
            if (vc == vcap) {
                vcap *= 2;
                verts = (Vec3 *)xrealloc(verts, (size_t)vcap * sizeof(Vec3));
            }
            verts[vc++] = (Vec3){x, y, z};
        } else if (s[0] == 'f' && isspace((unsigned char)s[1])) {
            int ids[3];
            char *p = s + 1;
            for (int k = 0; k < 3; k++) {
                while (isspace((unsigned char)*p)) p++;
                if (*p == '\0') {
                    setmsg(msg, msglen, "bad OBJ face");
                    goto fail;
                }
                errno = 0;
                long idx = strtol(p, &p, 10);
                if (errno || idx == 0) {
                    setmsg(msg, msglen, "bad OBJ face index");
                    goto fail;
                }
                if (idx < 0) idx = vc + idx + 1;
                ids[k] = (int)idx - 1;
                while (*p && !isspace((unsigned char)*p)) p++;
            }
            while (isspace((unsigned char)*p)) p++;
            if (*p && *p != '#') {
                setmsg(msg, msglen, "non-triangular OBJ face");
                goto fail;
            }
            if (fc == fcap) {
                fcap *= 2;
                faces = (Face *)xrealloc(faces, (size_t)fcap * sizeof(Face));
            }
            faces[fc++] = (Face){ids[0], ids[1], ids[2]};
        }
    }

    if (ferror(fp)) {
        snprintf(msg, msglen, "%s: read error", path);
        goto fail;
    }
    if (fclose(fp) != 0) {
        snprintf(msg, msglen, "%s: close error: %s", path, strerror(errno));
        free(verts);
        free(faces);
        return false;
    }

    *vertsout = verts;
    *nvout = vc;
    *facesout = faces;
    *nfout = fc;
    return true;

fail:
    fclose(fp);
    free(verts);
    free(faces);
    return false;
}

static bool check_oriented_sphere(int nv, int nf, const Face *faces, char *msg, size_t msglen)
{
    if (nv <= 0 || nf <= 0) {
        setmsg(msg, msglen, "needs vertices and triangular faces");
        return false;
    }
    size_t nn = (size_t)nv * (size_t)nv;
    if ((size_t)nv != 0 && nn / (size_t)nv != (size_t)nv) {
        setmsg(msg, msglen, "too many vertices");
        return false;
    }

    int *dir = (int *)xcalloc(nn, sizeof(int));
    int *nxt = (int *)xcalloc(nn, sizeof(int));
    bool *seen = (bool *)xcalloc((size_t)nv, sizeof(bool));
    for (size_t i = 0; i < nn; i++) {
        dir[i] = -1;
        nxt[i] = -1;
    }

    for (int f = 0; f < nf; f++) {
        int tri[3] = {faces[f].a, faces[f].b, faces[f].c};
        for (int k = 0; k < 3; k++) {
            int v = tri[k];
            if (v < 0 || v >= nv) {
                setmsg(msg, msglen, "face index out of range");
                goto fail;
            }
        }
        if (tri[0] == tri[1] || tri[0] == tri[2] || tri[1] == tri[2]) {
            setmsg(msg, msglen, "degenerate face");
            goto fail;
        }

        for (int k = 0; k < 3; k++) {
            int u = tri[k];
            int v = tri[(k + 1) % 3];
            if (dir[(size_t)u * (size_t)nv + (size_t)v] >= 0) {
                setmsg(msg, msglen, "duplicate directed edge");
                goto fail;
            }
            dir[(size_t)u * (size_t)nv + (size_t)v] = f;

            int center = tri[k];
            int x = tri[(k + 2) % 3];
            int y = tri[(k + 1) % 3];
            if (nxt[(size_t)center * (size_t)nv + (size_t)x] >= 0) {
                setmsg(msg, msglen, "duplicate oriented link step");
                goto fail;
            }
            nxt[(size_t)center * (size_t)nv + (size_t)x] = y;
        }
    }

    int ne = 0;
    for (int u = 0; u < nv; u++) {
        for (int v = u + 1; v < nv; v++) {
            int uv = dir[(size_t)u * (size_t)nv + (size_t)v];
            int vu = dir[(size_t)v * (size_t)nv + (size_t)u];
            if ((uv >= 0) != (vu >= 0)) {
                setmsg(msg, msglen, "edge is not paired with opposite orientation");
                goto fail;
            }
            if (uv >= 0) ne++;
        }
    }

    if (3 * nf != 2 * ne) {
        setmsg(msg, msglen, "edge/face count is not a closed triangulation");
        goto fail;
    }
    if (nv - ne + nf != 2) {
        setmsg(msg, msglen, "Euler characteristic is not 2");
        goto fail;
    }

    for (int v = 0; v < nv; v++) {
        int degree = 0;
        int start = -1;
        for (int j = 0; j < nv; j++) {
            if (nxt[(size_t)v * (size_t)nv + (size_t)j] >= 0) {
                if (start < 0) start = j;
                degree++;
            }
        }
        if (degree == 0) {
            setmsg(msg, msglen, "isolated vertex");
            goto fail;
        }
        memset(seen, 0, (size_t)nv * sizeof(bool));
        int cur = start;
        for (int k = 0; k < degree; k++) {
            if (cur < 0 || cur >= nv) {
                setmsg(msg, msglen, "broken oriented link");
                goto fail;
            }
            if (seen[cur]) {
                setmsg(msg, msglen, "oriented link is not a single cycle");
                goto fail;
            }
            seen[cur] = true;
            cur = nxt[(size_t)v * (size_t)nv + (size_t)cur];
        }
        if (cur != start) {
            setmsg(msg, msglen, "oriented link is disconnected");
            goto fail;
        }
    }

    snprintf(msg, msglen, "ok nv=%d nf=%d ne=%d", nv, nf, ne);
    free(dir);
    free(nxt);
    free(seen);
    return true;

fail:
    free(dir);
    free(nxt);
    free(seen);
    return false;
}

static bool check_netcode(const char *netcode, char *msg, size_t msglen)
{
    Face *faces = NULL;
    int nv = 0, nf = 0;
    if (!parse_netcode(netcode, &faces, &nv, &nf, msg, msglen)) return false;
    bool ok = check_oriented_sphere(nv, nf, faces, msg, msglen);
    free(faces);
    return ok;
}

static bool check_obj(const char *path, char *msg, size_t msglen)
{
    Vec3 *verts = NULL;
    Face *faces = NULL;
    int nv = 0, nf = 0;
    if (!read_obj(path, &verts, &nv, &faces, &nf, msg, msglen)) return false;
    bool ok = check_oriented_sphere(nv, nf, faces, msg, msglen);
    free(verts);
    free(faces);
    return ok;
}

static int run_batch(bool objs)
{
    char *line = NULL;
    size_t cap = 0;
    ssize_t len;
    long index = 0;
    int failures = 0;

    while ((len = getline(&line, &cap, stdin)) != -1) {
        (void)len;
        chomp(line);
        if (line[0] == '\0') continue;

        char msg[512] = {0};
        bool ok = objs ? check_obj(line, msg, sizeof(msg)) : check_netcode(line, msg, sizeof(msg));
        fprintf(stdout, "%ld\t%s\t%s\t%s\n", index, ok ? "ok" : "fail", line, msg);
        if (!ok) failures++;
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
    fprintf(stderr, "  %s --netcode NETCODE\n", prog);
    fprintf(stderr, "  %s --netcodes < netcodes.txt\n", prog);
    fprintf(stderr, "  %s --obj OBJFILE\n", prog);
    fprintf(stderr, "  %s --objs < objfiles.txt\n", prog);
}

int main(int argc, char **argv)
{
    if (argc == 3 && strcmp(argv[1], "--netcode") == 0) {
        char msg[512] = {0};
        bool ok = check_netcode(argv[2], msg, sizeof(msg));
        printf("%s: %s\n", ok ? "ok" : "fail", msg);
        return ok ? 0 : 1;
    }
    if (argc == 3 && strcmp(argv[1], "--obj") == 0) {
        char msg[512] = {0};
        bool ok = check_obj(argv[2], msg, sizeof(msg));
        printf("%s: %s\n", ok ? "ok" : "fail", msg);
        return ok ? 0 : 1;
    }
    if (argc == 2 && strcmp(argv[1], "--netcodes") == 0) return run_batch(false);
    if (argc == 2 && strcmp(argv[1], "--objs") == 0) return run_batch(true);

    usage(argv[0]);
    return 2;
}
