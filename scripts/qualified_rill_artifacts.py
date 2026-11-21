#!/usr/bin/env python3
"""Use the pinned package repository's qualification and byte verifier."""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path


def upstream(package_dir):
    path=package_dir/'scripts/qualified_runtime_artifacts.py'
    if not path.is_file():raise ValueError('pinned package checkout lacks the schema 4 qualified-byte verifier')
    spec=importlib.util.spec_from_file_location('qualified_runtime_upstream',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module


def fetch_manifest(run_id,attempt,package_commit,package_dir):
    return upstream(package_dir).fetch_manifest(run_id,attempt,package_commit,package_dir)


def fetch_stable(contract,package_dir,openwrt_version,architecture,pkgtype,output,apk='apk'):
    return upstream(package_dir).fetch_qualified(contract,package_dir,openwrt_version,
        architecture,pkgtype,output,apk,channel='stable')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract',type=Path,default=Path(__file__).resolve().parents[1]/'contracts/rill-runtime.json')
    parser.add_argument('--package-dir',type=Path,required=True)
    parser.add_argument('--channel',choices=['stable'],default='stable')
    parser.add_argument('--openwrt-version',required=True)
    parser.add_argument('--architecture',required=True)
    parser.add_argument('--pkgtype',choices=['ipk','apk'],required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--apk',default='apk')
    args=parser.parse_args()
    if args.channel != 'stable':
        raise ValueError('only the canonical Stable Runtime package is supported')
    path,target=fetch_stable(json.loads(args.contract.read_text()),args.package_dir,
        args.openwrt_version,args.architecture,args.pkgtype,args.output,args.apk)
    print(json.dumps({'package':str(path),'qualifiedTarget':target},indent=2))


if __name__=='__main__':main()
