"""Strict generic package migration evidence contract (historical aliases stay separate)."""
import re
from package_identity import split_version

SCENARIOS = {
 'a': (['legacyBase'], ['currentBase'], 'absent'),
 'b': (['legacyBase','legacyAddon'], ['currentBase'], 'retained'),
 'c': (['legacyBase','legacyAddon'], ['currentBase','currentAddon'], 'replaced'),
 'd': (['legacyBase','legacyAddon'], ['currentBase'], 'removed'),
 'e': (['recentBase'], ['currentBase'], 'absent'),
}
ROLES = {'legacyBase','legacyAddon','currentBase','currentAddon','recentBase'}


def need(condition, message):
    if not condition: raise ValueError('migration matrix: '+message)


def validate(matrices, assets):
    need(isinstance(matrices,list) and len(matrices)==2,'one matrix per package manager required')
    seen=set()
    for matrix in matrices:
        need(isinstance(matrix,dict) and type(matrix.get('schemaVersion')) is int and matrix['schemaVersion']==1,'unsupported schema')
        kind=matrix.get('packageManager')
        need(kind in ('ipk','apk') and kind not in seen,'missing or duplicate manager')
        seen.add(kind)
        inputs=matrix.get('inputs')
        need(isinstance(inputs,dict) and set(inputs)==ROLES,'input roles incomplete')
        for role,record in inputs.items():
            need(isinstance(record,dict),'input record missing')
            need(isinstance(record.get('sha256'),str) and re.fullmatch('[a-f0-9]{64}',record['sha256']),'invalid input digest')
            need(type(record.get('size')) is int and record['size']>0,'invalid input size')
            meta=record.get('package')
            need(isinstance(meta,dict),'input metadata missing')
            expected_name='luci-app-cloudflare-ip-rill' if role.endswith('Addon') else 'luci-app-cloudflare-ip'
            need(meta.get('name')==expected_name and meta.get('format')==kind,'input name/format mismatch')
            need(meta.get('architecture') in (('all',) if kind=='ipk' else ('all','noarch')),'input architecture mismatch')
            version,release=split_version(meta.get('packageVersion'),kind)
            need(meta.get('version')==version and type(meta.get('release')) is int and meta['release']==release,'raw/logical version mismatch')
        current=inputs['currentBase']['package']
        addon=inputs['currentAddon']['package']
        need(all(current[k]==addon[k] for k in ('version','release','packageVersion')),'candidate base/addon identity mismatch')
        public=[a for a in assets if a.get('package',{}).get('format')==kind]
        need(len(public)==1,'public package identity missing')
        need(all(current[k]==public[0]['package'].get(k) for k in ('version','release','packageVersion')),'migration candidate differs from release identity')
        conflict=matrix.get('ownershipConflict')
        need(isinstance(conflict,dict),'missing ownership conflict evidence')
        need(conflict.get('id')=='owner-conflict' and conflict.get('status')=='PASS','ownership conflict did not pass')
        need(type(conflict.get('exitCode')) is int and 1<=conflict['exitCode']<=255,'ownership conflict needs nonzero manager exit')
        need(all(conflict.get(k) is True for k in ('rejected','foreignOwnerPreserved','preexistingPayloadPreserved','installedStatePreserved','userDataPreserved')),'ownership conflict lost installed state or user data')
        need(conflict.get('evidenceDirectory')==kind+'-negative-owner-conflict','unsafe ownership conflict evidence directory')
        negative=matrix.get('negativeInstalls')
        need(isinstance(negative,list) and len(negative)==2,'missing negative install matrix')
        negative_ids=set()
        for row in negative:
            need(isinstance(row,dict),'invalid negative install record')
            key=row.get('id')
            need(isinstance(key,str) and key in ('missing','truncated') and key not in negative_ids,'unknown/duplicate negative install')
            negative_ids.add(key)
            need(type(row.get('exitCode')) is int and 1<=row['exitCode']<=255,'negative install missing nonzero manager exit')
            need(row.get('status')=='PASS' and all(row.get(k) is True for k in ('rejected','installedStatePreserved','payloadPreserved','userDataPreserved')),'negative install did not pass preservation checks')
            need(row.get('evidenceDirectory')==kind+'-negative-'+key,'unsafe negative install evidence directory')
        scenarios=matrix.get('scenarios')
        need(isinstance(scenarios,list) and len(scenarios)==len(SCENARIOS),'incomplete scenario set')
        ids=set()
        for row in scenarios:
            need(isinstance(row,dict),'invalid scenario')
            key=row.get('id')
            need(isinstance(key,str) and key in SCENARIOS and key not in ids,'unknown/duplicate scenario')
            ids.add(key)
            old,new,addon_action=SCENARIOS[key]
            need(row.get('from')==old and row.get('to')==new and row.get('addon')==addon_action,'scenario operation mismatch')
            need(row.get('status')=='PASS' and all(row.get(k) is True for k in ('runtimeAbsent','runtimePresent','userDataPreserved')),'scenario did not pass all checks')
            need(row.get('evidenceDirectory')==kind+'-'+key,'unsafe or wrong evidence directory')
