/* PTY spawning: forkpty on Unix, ConPTY on Windows.  The handle is a
   heap struct handed to OCaml as a nativeint and freed by
   lui_term_pty_close. */

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/bigarray.h>
#include <string.h>
#include <stdlib.h>

#if defined(_WIN32)

#include <windows.h>

typedef struct {
  HANDLE out_r;   /* console output, parent reads */
  HANDLE in_w;    /* console input, parent writes */
  HANDLE hpc;     /* pseudo console handle */
  HANDLE hproc;   /* child process */
  int exited;
  int exit_code;
} pty_t;

/* ConPTY entry points, resolved dynamically so any SDK level compiles. */
typedef HRESULT (WINAPI *CreatePseudoConsole_t)(COORD, HANDLE, HANDLE,
                                                DWORD, void **);
typedef HRESULT (WINAPI *ResizePseudoConsole_t)(void *, COORD);
typedef void (WINAPI *ClosePseudoConsole_t)(void *);

static CreatePseudoConsole_t p_CreatePseudoConsole = NULL;
static ResizePseudoConsole_t p_ResizePseudoConsole = NULL;
static ClosePseudoConsole_t p_ClosePseudoConsole = NULL;
static int conpty_resolved = 0;

static int resolve_conpty(void) {
  HMODULE k;
  if (conpty_resolved) return p_CreatePseudoConsole != NULL;
  conpty_resolved = 1;
  k = GetModuleHandleA("kernel32.dll");
  if (!k) return 0;
  p_CreatePseudoConsole =
    (CreatePseudoConsole_t)GetProcAddress(k, "CreatePseudoConsole");
  p_ResizePseudoConsole =
    (ResizePseudoConsole_t)GetProcAddress(k, "ResizePseudoConsole");
  p_ClosePseudoConsole =
    (ClosePseudoConsole_t)GetProcAddress(k, "ClosePseudoConsole");
  return p_CreatePseudoConsole != NULL &&
         p_ResizePseudoConsole != NULL &&
         p_ClosePseudoConsole != NULL;
}

/* Join argv into a quoted command line. */
static char *join_argv(value vargv) {
  mlsize_t n = Wosize_val(vargv), i;
  size_t len = 1;
  char *s, *p;
  for (i = 0; i < n; i++)
    len += caml_string_length(Field(vargv, i)) + 3;
  s = (char *)malloc(len);
  if (!s) return NULL;
  p = s;
  for (i = 0; i < n; i++) {
    value a = Field(vargv, i);
    size_t al = caml_string_length(a);
    int quote = 0;
    size_t j;
    if (i) *p++ = ' ';
    for (j = 0; j < al; j++)
      if (String_val(a)[j] == ' ' || String_val(a)[j] == '\t') quote = 1;
    if (quote) *p++ = '"';
    memcpy(p, String_val(a), al);
    p += al;
    if (quote) *p++ = '"';
  }
  *p = 0;
  return s;
}

/* Build the "K=V\0..\0" environment block. */
static char *join_env(value venv) {
  mlsize_t n = Wosize_val(venv), i;
  size_t len = 1;
  char *s, *p;
  for (i = 0; i < n; i++) len += caml_string_length(Field(venv, i)) + 1;
  s = (char *)malloc(len);
  if (!s) return NULL;
  p = s;
  for (i = 0; i < n; i++) {
    size_t al = caml_string_length(Field(venv, i));
    memcpy(p, String_val(Field(venv, i)), al);
    p += al;
    *p++ = 0;
  }
  *p = 0;
  return s;
}

CAMLprim value lui_term_pty_spawn(value vargv, value venv, value vcwd,
                                  value vcols, value vrows) {
  CAMLparam5(vargv, venv, vcwd, vcols, vrows);
  pty_t *p;
  HANDLE in_r = NULL, in_w = NULL, out_r = NULL, out_w = NULL;
  char *cmd = NULL, *env = NULL;
  STARTUPINFOEXW si;
  PROCESS_INFORMATION pi;
  SIZE_T alen;
  wchar_t *wcmd, *wcwd;
  int ok = 0;

  if (!resolve_conpty()) caml_failwith("pty: ConPTY unavailable");

  p = (pty_t *)calloc(1, sizeof(pty_t));
  if (!p) caml_failwith("pty: out of memory");
  p->exited = 0;

  {
    SECURITY_ATTRIBUTES sa;
    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = NULL;
    sa.bInheritHandle = TRUE;
    if (!CreatePipe(&in_r, &in_w, &sa, 0)) goto fail;
    if (!CreatePipe(&out_r, &out_w, &sa, 0)) goto fail;
    if (!SetHandleInformation(in_w, HANDLE_FLAG_INHERIT, 0)) goto fail;
    if (!SetHandleInformation(out_r, HANDLE_FLAG_INHERIT, 0)) goto fail;
  }
  {
    COORD size;
    size.X = (SHORT)Int_val(vcols);
    size.Y = (SHORT)Int_val(vrows);
    if (FAILED(p_CreatePseudoConsole(size, in_r, out_w, 0,
                                     (void **)&p->hpc)))
      goto fail;
  }
  /* the console owns the pipe ends it got; ours are released */
  CloseHandle(in_r); in_r = NULL;
  CloseHandle(out_w); out_w = NULL;

  cmd = join_argv(vargv);
  env = join_env(venv);
  if (!cmd || !env) goto fail;

  memset(&si, 0, sizeof(si));
  si.StartupInfo.cb = sizeof(si);
  InitializeProcThreadAttributeList(NULL, 1, 0, &alen);
  si.lpAttributeList = (PPROC_THREAD_ATTRIBUTE_LIST)malloc(alen);
  if (!si.lpAttributeList) goto fail;
  if (!InitializeProcThreadAttributeList(si.lpAttributeList, 1, 0, &alen))
    goto fail_si;
  if (!UpdateProcThreadAttribute(si.lpAttributeList, 0,
                                 PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE,
                                 p->hpc, sizeof(p->hpc), NULL, NULL))
    goto fail_si;

  /* command line and cwd to UTF-16 */
  {
    int cl = MultiByteToWideChar(CP_UTF8, 0, cmd, -1, NULL, 0);
    int wl = MultiByteToWideChar(CP_UTF8, 0, String_val(vcwd), -1, NULL, 0);
    wcmd = (wchar_t *)malloc(cl * sizeof(wchar_t));
    wcwd = (wchar_t *)malloc(wl * sizeof(wchar_t));
    MultiByteToWideChar(CP_UTF8, 0, cmd, -1, wcmd, cl);
    MultiByteToWideChar(CP_UTF8, 0, String_val(vcwd), -1, wcwd, wl);
  }
  memset(&pi, 0, sizeof(pi));
  if (!CreateProcessW(NULL, wcmd, NULL, NULL, FALSE,
                      EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                      env, wcwd, &si.StartupInfo, &pi))
    goto fail_w;

  p->hproc = pi.hProcess;
  CloseHandle(pi.hThread);
  p->in_w = in_w;
  p->out_r = out_r;
  free(wcmd); free(wcwd); free(cmd); free(env);
  DeleteProcThreadAttributeList(si.lpAttributeList);
  free(si.lpAttributeList);
  CAMLreturn(caml_copy_nativeint((intnat)p));

fail_w:
  free(wcmd); free(wcwd);
fail_si:
  DeleteProcThreadAttributeList(si.lpAttributeList);
  free(si.lpAttributeList);
fail:
  if (cmd) free(cmd);
  if (env) free(env);
  if (in_r) CloseHandle(in_r);
  if (in_w) CloseHandle(in_w);
  if (out_r) CloseHandle(out_r);
  if (out_w) CloseHandle(out_w);
  if (p->hpc) p_ClosePseudoConsole(p->hpc);
  free(p);
  caml_failwith("pty: CreateProcess/ConPTY failed");
}

CAMLprim value lui_term_pty_read(value vh, value vbuf, value voff,
                                 value vlen) {
  CAMLparam4(vh, vbuf, voff, vlen);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  DWORD avail = 0, got = 0;
  if (!PeekNamedPipe(p->out_r, NULL, 0, NULL, &avail, NULL))
    CAMLreturn(Val_int(-1));
  if (avail == 0) CAMLreturn(Val_int(0));
  if (!ReadFile(p->out_r, (char *)Bytes_val(vbuf) + Int_val(voff),
                (DWORD)Int_val(vlen), &got, NULL))
    CAMLreturn(Val_int(-1));
  CAMLreturn(Val_int((int)got));
}

CAMLprim value lui_term_pty_write(value vh, value vbuf, value voff,
                                  value vlen) {
  CAMLparam4(vh, vbuf, voff, vlen);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  DWORD put = 0;
  if (!WriteFile(p->in_w, (char *)Bytes_val(vbuf) + Int_val(voff),
                 (DWORD)Int_val(vlen), &put, NULL))
    CAMLreturn(Val_int(-1));
  CAMLreturn(Val_int((int)put));
}

CAMLprim value lui_term_pty_resize(value vh, value vcols, value vrows) {
  CAMLparam3(vh, vcols, vrows);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  COORD size;
  size.X = (SHORT)Int_val(vcols);
  size.Y = (SHORT)Int_val(vrows);
  p_ResizePseudoConsole(p->hpc, size);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_term_pty_poll(value vh) {
  CAMLparam1(vh);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  DWORD code = 0;
  if (p->exited) CAMLreturn(Val_int(p->exit_code));
  if (WaitForSingleObject(p->hproc, 0) != WAIT_OBJECT_0)
    CAMLreturn(Val_int(-1));
  GetExitCodeProcess(p->hproc, &code);
  p->exited = 1;
  p->exit_code = (int)code;
  CAMLreturn(Val_int((int)code));
}

CAMLprim value lui_term_pty_kill(value vh) {
  CAMLparam1(vh);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  if (!p->exited) {
    TerminateProcess(p->hproc, 1);
    p->exited = 1;
    p->exit_code = 1;
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_term_pty_close(value vh) {
  CAMLparam1(vh);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  if (p) {
    if (p->hproc) CloseHandle(p->hproc);
    if (p->hpc) p_ClosePseudoConsole(p->hpc);
    if (p->out_r) CloseHandle(p->out_r);
    if (p->in_w) CloseHandle(p->in_w);
    free(p);
  }
  CAMLreturn(Val_unit);
}

#elif defined(__unix__) || defined(__APPLE__) || defined(__linux__)

#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <termios.h>
#if defined(__APPLE__)
#include <util.h>
#else
#include <pty.h>
#endif

typedef struct {
  int mfd;
  pid_t pid;
  int exited;
  int exit_code;
} pty_t;

static char **strv(value v) {
  mlsize_t n = Wosize_val(v), i;
  char **out = (char **)malloc((n + 1) * sizeof(char *));
  if (!out) return NULL;
  for (i = 0; i < n; i++)
    out[i] = String_val(Field(v, i)); /* strings are NUL-terminated */
  out[n] = NULL;
  return out;
}

CAMLprim value lui_term_pty_spawn(value vargv, value venv, value vcwd,
                                  value vcols, value vrows) {
  CAMLparam5(vargv, venv, vcwd, vcols, vrows);
  pty_t *p;
  struct winsize ws;
  char **argv = NULL, **env = NULL;
  pid_t pid;

  p = (pty_t *)calloc(1, sizeof(pty_t));
  if (!p) caml_failwith("pty: out of memory");
  argv = strv(vargv);
  env = strv(venv);
  if (!argv || !env) caml_failwith("pty: out of memory");

  memset(&ws, 0, sizeof(ws));
  ws.ws_col = (unsigned short)Int_val(vcols);
  ws.ws_row = (unsigned short)Int_val(vrows);

  pid = forkpty(&p->mfd, NULL, NULL, &ws);
  if (pid < 0) {
    free(argv); free(env); free(p);
    caml_failwith("pty: forkpty failed");
  }
  if (pid == 0) {
    if (caml_string_length(vcwd) > 0)
      (void)!chdir(String_val(vcwd));
    execvp(argv[0], argv);
    _exit(127);
  }
  free(argv); free(env);
  p->pid = pid;
  p->exited = 0;
  /* master: nonblocking so the UI loop can poll freely */
  fcntl(p->mfd, F_SETFL, fcntl(p->mfd, F_GETFL) | O_NONBLOCK);
  CAMLreturn(caml_copy_nativeint((intnat)p));
}

CAMLprim value lui_term_pty_read(value vh, value vbuf, value voff,
                                 value vlen) {
  CAMLparam4(vh, vbuf, voff, vlen);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  ssize_t n;
  do {
    n = read(p->mfd, (char *)Bytes_val(vbuf) + Int_val(voff),
             (size_t)Int_val(vlen));
  } while (n < 0 && errno == EINTR);
  if (n == 0 || (n < 0 && errno == EIO)) CAMLreturn(Val_int(-1));
  if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
    CAMLreturn(Val_int(0));
  if (n < 0) CAMLreturn(Val_int(-1));
  CAMLreturn(Val_int((int)n));
}

CAMLprim value lui_term_pty_write(value vh, value vbuf, value voff,
                                  value vlen) {
  CAMLparam4(vh, vbuf, voff, vlen);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  ssize_t n;
  do {
    n = write(p->mfd, (char *)Bytes_val(vbuf) + Int_val(voff),
              (size_t)Int_val(vlen));
  } while (n < 0 && errno == EINTR);
  if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK))
    CAMLreturn(Val_int(0));
  if (n < 0) CAMLreturn(Val_int(-1));
  CAMLreturn(Val_int((int)n));
}

CAMLprim value lui_term_pty_resize(value vh, value vcols, value vrows) {
  CAMLparam3(vh, vcols, vrows);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  struct winsize ws;
  memset(&ws, 0, sizeof(ws));
  ws.ws_col = (unsigned short)Int_val(vcols);
  ws.ws_row = (unsigned short)Int_val(vrows);
  (void)ioctl(p->mfd, TIOCSWINSZ, &ws);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_term_pty_poll(value vh) {
  CAMLparam1(vh);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  int st;
  pid_t r;
  if (p->exited) CAMLreturn(Val_int(p->exit_code));
  r = waitpid(p->pid, &st, WNOHANG);
  if (r == 0) CAMLreturn(Val_int(-1));
  if (r < 0) CAMLreturn(Val_int(-1));
  p->exited = 1;
  if (WIFEXITED(st)) p->exit_code = WEXITSTATUS(st);
  else if (WIFSIGNALED(st)) p->exit_code = 128 + WTERMSIG(st);
  else p->exit_code = 0;
  CAMLreturn(Val_int(p->exit_code));
}

CAMLprim value lui_term_pty_kill(value vh) {
  CAMLparam1(vh);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  if (!p->exited) {
    /* the child is a session leader: take the whole group down */
    kill(-p->pid, SIGKILL);
    kill(p->pid, SIGKILL);
    (void)waitpid(p->pid, NULL, 0);
    p->exited = 1;
    p->exit_code = 137;
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_term_pty_close(value vh) {
  CAMLparam1(vh);
  pty_t *p = (pty_t *)(intnat)Nativeint_val(vh);
  if (p) {
    if (p->mfd >= 0) close(p->mfd);
    free(p);
  }
  CAMLreturn(Val_unit);
}

#else

CAMLprim value lui_term_pty_spawn(value vargv, value venv, value vcwd,
                                  value vcols, value vrows) {
  CAMLparam5(vargv, venv, vcwd, vcols, vrows);
  caml_failwith("pty: unsupported platform");
}

CAMLprim value lui_term_pty_read(value vh, value vb, value vo, value vl) {
  CAMLparam4(vh, vb, vo, vl);
  caml_failwith("pty: unsupported platform");
}
CAMLprim value lui_term_pty_write(value vh, value vb, value vo, value vl) {
  CAMLparam4(vh, vb, vo, vl);
  caml_failwith("pty: unsupported platform");
}
CAMLprim value lui_term_pty_resize(value vh, value vc, value vr) {
  CAMLparam3(vh, vc, vr);
  caml_failwith("pty: unsupported platform");
}
CAMLprim value lui_term_pty_poll(value vh) {
  CAMLparam1(vh);
  caml_failwith("pty: unsupported platform");
}
CAMLprim value lui_term_pty_kill(value vh) {
  CAMLparam1(vh);
  caml_failwith("pty: unsupported platform");
}
CAMLprim value lui_term_pty_close(value vh) {
  CAMLparam1(vh);
  caml_failwith("pty: unsupported platform");
}

#endif
