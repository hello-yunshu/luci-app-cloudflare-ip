#!/usr/bin/env python3
"""Host-only flock CLI adapter; uses the real kernel flock syscall on an inherited FD."""
import fcntl
import os
import sys
if len(sys.argv)!=3 or sys.argv[1] not in ('-n','-u'):
    raise SystemExit(2)
fd=int(sys.argv[2]);os.fstat(fd)
try:fcntl.flock(fd,fcntl.LOCK_UN if sys.argv[1]=='-u' else fcntl.LOCK_EX|fcntl.LOCK_NB)
except BlockingIOError:raise SystemExit(1)
