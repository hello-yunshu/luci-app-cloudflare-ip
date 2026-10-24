#!/usr/bin/env python3
"""Read-only APK ownership admission; run before apk add, not a transaction/CAS."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys


def relative(value, allow_empty=False):
    if not isinstance(value, str) or (not value and not allow_empty):
        raise ValueError('missing package path')
    if value == '' and allow_empty:
        return ''
    p=PurePosixPath(value)
    if p.is_absolute() or any(x in ('', '.', '..') for x in value.split('/')) or '\x00' in value or '\n' in value:
        raise ValueError('unsafe package path')
    return value


def inspect(root, package, apk):
    db=root/'lib/apk/db/installed'
    # Refuse an unknown/missing ownership database rather than assume no owners.
    data=db.read_bytes()
    owners={}
    for block in data.decode().split('\n\n'):
        if not block.strip(): continue
        name=None;directory=None
        for line in block.splitlines():
            key,sep,value=line.partition(':')
            if not sep: raise ValueError('malformed installed database record')
            if key=='P':
                if name is not None or not value: raise ValueError('invalid installed package identity')
                name=value
            elif key=='F':directory=relative(value,True)
            elif key=='R':
                if not name or directory is None: raise ValueError('file without installed owner/directory')
                filename=relative(value)
                if '/' in filename: raise ValueError('invalid installed basename')
                path=directory+'/'+filename if directory else filename
                if path in owners and owners[path]!=name: raise ValueError('ambiguous installed ownership: '+path)
                owners[path]=name
        if not name: raise ValueError('installed record has no package identity')
    raw=package.read_bytes()
    result=subprocess.run([apk,'--allow-untrusted','adbdump','--format','json',str(package)],capture_output=True,text=True,timeout=30)
    if result.returncode: raise ValueError('APK metadata reader failed: '+result.stderr[-300:])
    value=json.loads(result.stdout)
    if not isinstance(value,dict) or value.get('info',{}).get('name')!='luci-app-cloudflare-ip':
        raise ValueError('not the expected candidate package')
    paths=value.get('paths')
    if not isinstance(paths,list) or not paths: raise ValueError('missing APK payload paths')
    files=set();conflicts=[]
    for row in paths:
        directory=relative(row.get('name',''),True)
        for entry in row.get('files',[]):
            filename=relative(entry.get('name'))
            if '/' in filename: raise ValueError('invalid candidate basename')
            path=directory+'/'+filename if directory else filename
            if path in files: raise ValueError('duplicate candidate payload path')
            files.add(path)
            owner=owners.get(path)
            if owner and owner!='luci-app-cloudflare-ip':conflicts.append(dict(path=path,owner=owner))
            # A parent link could redirect installation outside the inspected root.
            target=root/path
            if any(parent.is_symlink() for parent in target.parents if parent!=root and root in parent.parents):
                raise ValueError('candidate parent is a symbolic link: '+path)
    if 'usr/bin/cf-ip-auto' not in files: raise ValueError('candidate payload is incomplete')
    # Bind observations and detect in-process changes, without claiming global CAS.
    if db.read_bytes()!=data or package.read_bytes()!=raw: raise ValueError('package or ownership database changed during preflight')
    return dict(success=not conflicts,scope='read-only ownership admission; not transactional installation',packageSha256=hashlib.sha256(raw).hexdigest(),installedDbSha256=hashlib.sha256(data).hexdigest(),payloadFiles=len(files),conflicts=conflicts)


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('package',type=Path);p.add_argument('--root',type=Path,required=True);p.add_argument('--apk-bin',default='apk')
    a=p.parse_args()
    try:
        result=inspect(a.root.resolve(),a.package.resolve(),a.apk_bin)
        print(json.dumps(result,sort_keys=True));return 0 if result['success'] else 65
    except (OSError,ValueError,TypeError,KeyError,AttributeError,subprocess.SubprocessError) as error:
        print(json.dumps(dict(success=False,error=str(error))));return 65
if __name__=='__main__':sys.exit(main())
