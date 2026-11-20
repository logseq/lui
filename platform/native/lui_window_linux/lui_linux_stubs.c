/* Native helpers for the Linux window host: select() on raw ints so
   the wait loop can watch D-Bus fds without a magic file_descr cast. */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/threads.h>

#if defined(__linux__)

#include <errno.h>
#include <sys/select.h>

CAMLprim value lui_linux_select_readable(value vfds, value vtimeout)
{
	CAMLparam2(vfds, vtimeout);
	int fds[FD_SETSIZE];
	int n = 0, i, maxfd = -1, r;
	fd_set rfds;
	double t;
	struct timeval tv, *ptv = NULL;

	for (; vfds != Val_emptylist && n < FD_SETSIZE; vfds = Field(vfds, 1)) {
		int fd = Int_val(Field(vfds, 0));
		if (fd >= 0 && fd < FD_SETSIZE)
			fds[n++] = fd;
	}
	t = Double_val(vtimeout);
	if (t >= 0.) {
		if (t > 1e6)
			t = 1e6;
		tv.tv_sec = (time_t)t;
		tv.tv_usec = (suseconds_t)((t - (double)tv.tv_sec) * 1e6);
		if (tv.tv_usec < 0)
			tv.tv_usec = 0;
		ptv = &tv;
	}

	caml_release_runtime_system();
	do {
		FD_ZERO(&rfds);
		maxfd = -1;
		for (i = 0; i < n; i++) {
			FD_SET(fds[i], &rfds);
			if (fds[i] > maxfd)
				maxfd = fds[i];
		}
		r = (maxfd < 0) ? 0 : select(maxfd + 1, &rfds, NULL, NULL, ptv);
	} while (r < 0 && errno == EINTR);
	caml_acquire_runtime_system();
	CAMLreturn(Val_int(r < 0 ? 0 : r));
}

#else

CAMLprim value lui_linux_select_readable(value vfds, value vtimeout)
{
	(void)vfds;
	(void)vtimeout;
	return Val_int(0);
}

#endif
