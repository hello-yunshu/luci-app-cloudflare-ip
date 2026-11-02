#!/usr/bin/env python3
"""Prepare a real amd64 smoke binary only after release digest/ELF validation."""
import argparse
import hashlib
import json
import re
import tarfile
from pathlib import Path, PurePosixPath

MAX_ARCHIVE=64*1024*1024
MAX_BINARY=32*1024*1024
ASSET='cfst_linux_amd64.tar.gz'


def require(ok,message):
    if not ok: raise ValueError(message)


def select_asset(release):
    require(isinstance(release,dict),'release metadata must be an object')
    require(type(release.get('id')) is int and release['id']>0,'release ID required')
    tag=release.get('tag_name')
    require(isinstance(tag,str) and re.fullmatch(r'[A-Za-z0-9._-]+',tag),'invalid release tag')
    assets=release.get('assets')
    require(isinstance(assets,list),'asset list missing')
    matches=[a for a in assets if isinstance(a,dict) and a.get('name')==ASSET]
    require(len(matches)==1,'exactly one amd64 asset required')
    asset=matches[0]
    require(type(asset.get('id')) is int and asset['id']>0,'asset ID required')
    require(type(asset.get('size')) is int and 0<asset['size']<=MAX_ARCHIVE,'invalid or oversized asset')
    require(isinstance(asset.get('digest'),str) and re.fullmatch(r'sha256:[a-f0-9]{64}',asset['digest']),'published SHA256 digest required before execution')
    expected=f'https://github.com/XIU2/CloudflareSpeedTest/releases/download/{tag}/{ASSET}'
    require(asset.get('browser_download_url')==expected,'asset URL differs from official release identity')
    return asset


def prepare(release,archive,output):
    asset=select_asset(release)
    require(not output.exists() and not output.is_symlink(),'output must be new')
    require(archive.is_file() and not archive.is_symlink(),'archive must be a regular file')
    require(archive.stat().st_size==asset['size'],'archive size differs from metadata')
    require(archive.stat().st_size<=MAX_ARCHIVE,'archive exceeds cap')
    digest=hashlib.sha256(archive.read_bytes()).hexdigest()
    require('sha256:'+digest==asset['digest'],'archive digest mismatch')
    binary=None;names=set();total=0;count=0
    # Only read one member into memory. Never extract paths into the filesystem.
    with tarfile.open(archive,mode='r|gz') as tar:
        for member in tar:
            count+=1
            require(count<=128,'too many archive entries')
            name=member.name
            while name.startswith('./'):name=name[2:]
            path=PurePosixPath(name)
            require(name and not path.is_absolute() and '..' not in path.parts and '\\' not in name,'unsafe archive path')
            require(name not in names,'duplicate archive path');names.add(name)
            require(member.isdir() or member.isfile(),'archive links/devices are forbidden')
            total+=member.size
            require(total<=128*1024*1024,'archive expanded size exceeds cap')
            if path.name=='cfst':
                require(member.isfile() and binary is None and 0<member.size<=MAX_BINARY,'invalid or duplicate binary')
                stream=tar.extractfile(member)
                require(stream is not None,'binary member unreadable')
                binary=stream.read(MAX_BINARY+1)
                require(len(binary)==member.size,'binary size mismatch')
    require(binary is not None,'cfst binary missing')
    require(len(binary)>=20 and binary[:4]==b'\x7fELF' and binary[4:6]==b'\x02\x01','not a little-endian ELF64 binary')
    require(int.from_bytes(binary[18:20],'little')==62,'ELF architecture is not amd64')
    require(int.from_bytes(binary[16:18],'little') in (2,3),'ELF is not executable/shared executable')
    receipt=dict(schemaVersion=1,releaseId=release['id'],tag=release['tag_name'],assetId=asset['id'],assetName=asset['name'],archiveSha256=digest,archiveSize=asset['size'],binarySha256=hashlib.sha256(binary).hexdigest(),binarySize=len(binary),architecture='amd64',execution='NOT RUN')
    output.mkdir()
    target=output/'cfst';target.write_bytes(binary);target.chmod(0o600)
    (output/'cfst-byte-qualification.json').write_text(json.dumps(receipt,indent=2)+'\n')
    target.chmod(0o755)
    return target


def main():
    p=argparse.ArgumentParser(description=__doc__)
    sub=p.add_subparsers(dest='command',required=True)
    url=sub.add_parser('asset-url');url.add_argument('metadata',type=Path)
    verify=sub.add_parser('verify');verify.add_argument('metadata',type=Path);verify.add_argument('archive',type=Path);verify.add_argument('output',type=Path)
    a=p.parse_args()
    try:
        release=json.loads(a.metadata.read_text())
        if a.command=='asset-url':print(select_asset(release)['browser_download_url'])
        else:print(prepare(release,a.archive,a.output))
    except (OSError,ValueError,KeyError,TypeError,tarfile.TarError) as exc:
        p.exit(1,f'CFST qualification rejected: {exc}\n')


if __name__=='__main__':main()
