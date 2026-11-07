#!/usr/bin/env python3
"""Upload prepared screenshots to the existing draft listing, without submitting it."""
import hashlib
import importlib.util
import json
import struct
import urllib.request
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('asc', ROOT / 'release/app-store-api.py')
asc = importlib.util.module_from_spec(spec); spec.loader.exec_module(asc)
metadata = json.loads((ROOT / 'release/metadata.json').read_text())
app_id = metadata['appStoreConnectAppId']
versions = asc.request('GET', '/v1/apps/' + app_id + '/appStoreVersions')['data']
version = next(v for v in versions if v['attributes']['platform'] == 'IOS' and v['attributes']['versionString'] == metadata['version'])
if version['attributes']['appStoreState'] != 'PREPARE_FOR_SUBMISSION':
    raise RuntimeError('Screenshot upload requires a draft version')
localizations = asc.request('GET', '/v1/appStoreVersions/' + version['id'] + '/appStoreVersionLocalizations')['data']
localization = next(v for v in localizations if v['attributes']['locale'] == metadata['primaryLocale'])['id']
library = asc.request('GET', '/v1/apps/' + app_id + '/assetLibrary')['data']['id']
specs = asc.request('GET', '/v1/appAssetLibraryRefData')['data'][0]['attributes']['imageSpecs']
journal_path = ROOT / '.sdk/app-store-connect/approved-screenshot-uploads.json'
journal = json.loads(journal_path.read_text()) if journal_path.exists() else {}
for folder, group in [('iphone-6.3','IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE'),('iphone-6.9','IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE')]:
    ordered = []
    for mode in ['01-control','02-colors','03-animations','04-settings','05-matter']:
        file = ROOT / 'release/marketing-v2' / ('iphone-6.3' if folder == 'iphone-6.3' else '') / (mode + '.png')
        data = file.read_bytes(); digest = hashlib.sha256(data).hexdigest()
        name = folder + '-' + mode + '.png'
        width,height = struct.unpack('>II',data[16:24])
        expected_specs = [s['specId'] for s in specs if s['dimensions']['minWidth'] <= width <= s['dimensions']['maxWidth'] and s['dimensions']['minHeight'] <= height <= s['dimensions']['maxHeight'] and 'APP_SCREENSHOT' in s['compatiblePlacementTypes']]
        if not expected_specs: raise RuntimeError('Screenshot dimensions are not accepted: ' + name)
        entry = journal.get(name)
        if entry and entry['sha256'] != digest:
            raise RuntimeError('Screenshot changed; review existing placements before replacing ' + name)
        if not entry:
            image = asc.request('POST','/v1/appAssetLibraryImages',{'data':{'type':'appAssetLibraryImages','attributes':{'fileName':name,'fileSize':len(data),'category':'APP_SCREENSHOTS_AND_PREVIEWS','referenceName':'Luxio '+metadata['version']+' '+folder+' '+mode},'relationships':{'assetLibrary':{'data':{'type':'appAssetLibraries','id':library}}}}})['data']
            entry = {'imageId':image['id'],'sha256':digest,'group':group};journal[name]=entry
            journal_path.write_text(json.dumps(journal,indent=2)+'\n')
        else:
            image = asc.request('GET','/v1/appAssetLibraryImages/'+entry['imageId'])['data']
        state = image['attributes']['state']
        if state == 'AWAITING_UPLOAD':
            for op in image['attributes']['uploadOperations']:
                url=op['url'];host=urllib.parse.urlparse(url).hostname
                if not url.startswith('https://') or not host or not (host.endswith('.apple.com') or host.endswith('.icloud.com')):
                    raise RuntimeError('Unexpected upload destination')
                req=urllib.request.Request(url,data=data[op['offset']:op['offset']+op['length']],headers={h['name']:h['value'] for h in op['requestHeaders']},method=op['method'])
                with urllib.request.urlopen(req,timeout=90) as response: response.read()
            image=asc.request('PATCH','/v1/appAssetLibraryImages/'+entry['imageId'],{'data':{'type':'appAssetLibraryImages','id':entry['imageId'],'attributes':{'uploaded':True}}})['data']
        if image['attributes']['state']=='FAILED':
            raise RuntimeError('Apple rejected '+name+': '+json.dumps(image['attributes'].get('stateDetails')))
        if image['attributes'].get('specId') and image['attributes']['specId'] not in expected_specs:
            raise RuntimeError('Apple matched unexpected dimensions for '+name)
        if not entry.get('placementId'):
            placements=asc.request('GET','/v1/appAssetLibraryImages/'+entry['imageId']+'/placements?filter[appStoreVersionLocalization]='+localization)['data']
            placement=next((p for p in placements if p['attributes']['placementGroup']==group),None)
            if not placement:
                placement=asc.request('POST','/v1/appAssetLibraryPlacements',{'data':{'type':'appAssetLibraryPlacements','attributes':{'placementType':'APP_SCREENSHOT','placementGroup':group},'relationships':{'image':{'data':{'type':'appAssetLibraryImages','id':entry['imageId']}},'appStoreVersionLocalization':{'data':{'type':'appStoreVersionLocalizations','id':localization}}}}})['data']
            entry['placementId']=placement['id'];journal_path.write_text(json.dumps(journal,indent=2)+'\n')
        ordered.append({'type':'appAssetLibraryPlacements','id':entry['placementId']})
        print('Uploaded and placed',name,flush=True)
print('Approved images uploaded and placed. Existing screenshots remain until processing and final ordering are verified.',flush=True)
