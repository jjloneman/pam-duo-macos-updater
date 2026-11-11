/*
 * A stand-in for the installed Duo PAM module, for machines without one, such
 * as CI. It passes every check verify_module makes on a real module:
 *
 * - It's an arm64 bundle that loads only libraries under /usr/lib.
 *
 * - It exports pam_sm_authenticate, and loads with dlopen.
 *
 * - Its text carries OpenSSL's version line, OpenSSL's bare version, Duo's bare
 *   version and the root-owned OpenSSL config folder, as a real build's does.
 *
 * It does nothing else, so it can never stand in for the module at runtime.
 */
const char *const pam_duo_fixture_text[] = {
    "OpenSSL 3.5.9 29 Sep 2026",
    "3.5.9",
    "2.3.0",
    "OPENSSLDIR: \"/etc/duo/ssl\"",
};

int pam_sm_authenticate(void) { return pam_duo_fixture_text[0] == 0; }
