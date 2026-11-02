#!/usr/bin/env python3
"""Expanded package prerm with controlled init failures; no real service/cache writes."""
from pathlib import Path
import os,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
text=(ROOT/'package/luci-app-cloudflare-ip/Makefile').read_text()
script=text.split('define Package/luci-app-cloudflare-ip/prerm\n',1)[1].split('\nendef',1)[0].replace('\\\n','\n').replace('$$','$')
with tempfile.TemporaryDirectory() as directory:
 root=Path(directory);log=root/'calls';init=root/'init';init.mkdir()
 for name in ['cf_ip','cf_ip_publisher']:
  f=init/name;f.write_text('#!/bin/sh\nprintf "%s %s\\n" "${0##*/}" "$1" >>"$CALLS"\nif [ "${0##*/}:$1" = "$FAIL_ACTION" ]; then echo "controlled $FAIL_ACTION failure" >&2; exit 23; fi\n');f.chmod(0o755)
 script=script.replace('/etc/init.d/cf_ip_publisher',str(init/'cf_ip_publisher')).replace('/etc/init.d/cf_ip',str(init/'cf_ip')).replace('/tmp/luci-indexcache.',str(root/'luci-indexcache.')).replace('/tmp/luci-modulecache/',str(root/'luci-modulecache/'))
 hook=root/'prerm';hook.write_text(script)
 for action in ['cf_ip:stop','cf_ip_publisher:stop','cf_ip:disable','none']:
  log.unlink(missing_ok=True)
  p=subprocess.run(['/bin/sh',str(hook)],env=dict(os.environ,CALLS=str(log),FAIL_ACTION=action,IPKG_INSTROOT=''),capture_output=True,text=True)
  calls=log.read_text().splitlines()
  if action=='none':assert p.returncode==0 and calls==['cf_ip stop','cf_ip_publisher stop','cf_ip disable'],(action,p.returncode,calls)
  else:
   assert p.returncode!=0,(action,'prerm accepted lifecycle failure',calls)
   assert 'failure' in p.stderr,(action,'root error lost')
   expected=['cf_ip stop','cf_ip_publisher stop','cf_ip disable'];n=expected.index(action.replace(':',' '));assert calls==expected[:n+1],(action,'continued after failure',calls)
  print('PASS',action)
 log.unlink()
 p=subprocess.run(['/bin/sh',str(hook)],env=dict(os.environ,CALLS=str(log),FAIL_ACTION='none',IPKG_INSTROOT=str(root/'offline')),capture_output=True,text=True)
 assert p.returncode==0 and not log.exists(),'offline hook touched services'
 print('PASS offline root does not run online lifecycle')
