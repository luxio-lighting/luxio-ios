#!/usr/bin/env python3
"""Replace the old iPhone draft screenshots with the approved, processed set."""
import importlib.util
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('asc',ROOT/'release/app-store-api.py')
asc=importlib.util.module_from_spec(spec);spec.loader.exec_module(asc)
localization='f297e53a-2475-4b47-8cfe-2d237516541c'
version=asc.request('GET','/v1/appStoreVersions/c36b2926-39e2-4733-8c5d-70cd6eb33b08')['data']
assert version['attributes']['appStoreState']=='PREPARE_FOR_SUBMISSION'
new=json.loads((ROOT/'.sdk/app-store-connect/approved-screenshot-uploads.json').read_text())
old=json.loads((ROOT/'.sdk/app-store-connect/screenshot-uploads.json').read_text())
assert len(new)==10 and all(v.get('placementId') for v in new.values())
for name,item in new.items():
 image=asc.request('GET','/v1/appAssetLibraryImages/'+item['imageId'])['data']
 if image['attributes']['state']!='PREPARE_FOR_SUBMISSION': raise RuntimeError(name+' is not ready: '+image['attributes']['state'])
placements=asc.request('GET','/v1/appStoreVersionLocalizations/'+localization+'/placements?limit=200')['data']
existing={p['id']:p for p in placements}
for name,item in old.items():
 if not name.startswith('iphone-'): continue
 if item['placementId'] in existing:
  placement=existing[item['placementId']]
  assert placement['attributes']['placementGroup']==item['group']
  asc.request('DELETE','/v1/appAssetLibraryPlacements/'+item['placementId'])
  print('Replaced old placement:',name,flush=True)
for group in ['IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE','IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE']:
 ordered=[{'type':'appAssetLibraryPlacements','id':item['placementId']} for name,item in sorted(new.items()) if item['group']==group]
 assert len(ordered)==5
 asc.request('POST','/v1/appAssetLibraryPlacementOrderingRequests',{'data':{'type':'appAssetLibraryPlacementOrderingRequests','attributes':{'placementGroup':group},'relationships':{'orderedPlacements':{'data':ordered},'appStoreVersionLocalization':{'data':{'type':'appStoreVersionLocalizations','id':localization}}}}})
 result=asc.request('GET','/v1/appStoreVersionLocalizations/'+localization+'/placements?filter[placementGroup]='+group+'&sort=placementGroupPosition')['data']
 assert [p['id'] for p in result]==[p['id'] for p in ordered], 'Screenshot ordering differs'
 print('Verified five screenshots in order:',group,flush=True)
(ROOT/'release/marketing-v2/app-store-status.json').write_text(json.dumps({'version':'1.0.0','locale':'en-US','status':'Approved screenshots uploaded, processed, placed and ordered','iphoneSizes':['6.3','6.9'],'screenshotsPerSize':5,'ipad':'Existing tablet screenshots retained','submittedForReview':False},indent=2)+'\n')
