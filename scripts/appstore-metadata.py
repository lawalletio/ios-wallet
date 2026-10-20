#!/usr/bin/env python3
"""Push AppStore/metadata/ to App Store Connect for the version being prepared.

    pip install pyjwt cryptography requests
    ASC_KEY_PATH=… ASC_KEY_ID=… ASC_ISSUER_ID=… \
    REVIEW_FIRST_NAME=… REVIEW_LAST_NAME=… REVIEW_EMAIL=… [REVIEW_PHONE=…] \
    scripts/appstore-metadata.py [--build 12]

Idempotent: re-running updates what changed. Screenshots, the App Privacy answers, pricing/availability and the
final "Submit for Review" stay manual (see AppStore/README.md).
"""
import argparse, json, os, pathlib, re, sys, time

import jwt
import requests

ROOT = pathlib.Path(__file__).resolve().parent.parent
META = ROOT / "AppStore" / "metadata"
BUNDLE_ID = "io.lawallet.wallet"
BASE = "https://api.appstoreconnect.apple.com"


def token():
    now = int(time.time())
    return jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                      pathlib.Path(os.environ["ASC_KEY_PATH"]).read_text(), algorithm="ES256",
                      headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def call(method, path, body=None, params=None):
    r = requests.request(method, BASE + path, params=params, data=json.dumps(body) if body else None, timeout=60,
                         headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    if r.status_code >= 400:
        sys.exit(f"{method} {path} → {r.status_code}\n{r.text[:1500]}")
    return r.json() if r.text else {}


def text(locale, name):
    f = META / locale / f"{name}.txt"
    return f.read_text().strip() if f.exists() else None


def upsert(kind, existing, parent_rel, parent_id, locale, attrs):
    attrs = {k: v for k, v in attrs.items() if v is not None}
    if existing:
        call("PATCH", f"/v1/{kind}/{existing['id']}", {"data": {"type": kind, "id": existing["id"], "attributes": attrs}})
    else:
        call("POST", f"/v1/{kind}", {"data": {"type": kind, "attributes": {"locale": locale, **attrs},
                                              "relationships": {parent_rel: {"data": {"type": parent_rel + "s", "id": parent_id}}}}})
    print(f"  {kind} {locale} ✓")


SHOTS = ROOT / "AppStore" / "screenshots"
SHOT_LOCALES = {"en": "en-US", "es": "es-MX"}


def upload_screenshots(vid):
    """6.9" iPhone set (1320×2868 fills the APP_IPHONE_67 slot), replaced wholesale, in file-name order."""
    import hashlib
    locs = {l["attributes"]["locale"]: l["id"] for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]}
    for folder, locale in SHOT_LOCALES.items():
        files = sorted((SHOTS / folder).glob("*.png"))
        if not files or locale not in locs:
            continue
        sets = call("GET", f"/v1/appStoreVersionLocalizations/{locs[locale]}/appScreenshotSets")["data"]
        for old in (x for x in sets if x["attributes"]["screenshotDisplayType"] == "APP_IPHONE_67"):
            call("DELETE", f"/v1/appScreenshotSets/{old['id']}")
        set_id = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": "APP_IPHONE_67"},
            "relationships": {"appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": locs[locale]}}}}})["data"]["id"]
        for f in files:
            data = f.read_bytes()
            shot = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots",
                "attributes": {"fileName": f.name, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}}}})["data"]
            for op in shot["attributes"]["uploadOperations"]:
                chunk = data[op["offset"]:op["offset"] + op["length"]]
                r = requests.request(op["method"], op["url"], data=chunk, timeout=120,
                                     headers={h["name"]: h["value"] for h in op["requestHeaders"]})
                r.raise_for_status()
            call("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {"type": "appScreenshots", "id": shot["id"],
                 "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
        print(f"  screenshots {locale}: {len(files)} ✓")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", help="build number to attach to the version")
    ap.add_argument("--screenshots", action="store_true",
                    help="replace the 6.9\" screenshots with AppStore/screenshots/{en,es}/*.png (scripts/screenshots.sh)")
    args = ap.parse_args()
    locales = sorted(p.name for p in META.iterdir() if p.is_dir() and re.fullmatch(r"[a-z]{2}-[A-Z]{2}", p.name))
    marketing = re.search(r'MARKETING_VERSION: "([^"]+)"', (ROOT / "project.yml").read_text()).group(1)

    app = call("GET", "/v1/apps", params={"filter[bundleId]": BUNDLE_ID})["data"][0]
    app_id = app["id"]
    print(f"{app['attributes']['name']} ({app_id})")
    call("PATCH", f"/v1/apps/{app_id}", {"data": {"type": "apps", "id": app_id,
                                                  "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})

    # App info: categories + per-locale name/subtitle/privacy URL.
    info = next(i for i in call("GET", f"/v1/apps/{app_id}/appInfos")["data"]
                if i["attributes"]["state"] != "READY_FOR_DISTRIBUTION")
    call("PATCH", f"/v1/appInfos/{info['id']}", {"data": {"type": "appInfos", "id": info["id"], "relationships": {
        "primaryCategory": {"data": {"type": "appCategories", "id": "FINANCE"}},
        "secondaryCategory": {"data": {"type": "appCategories", "id": "UTILITIES"}}}}})
    print("  categories Finance / Utilities ✓")
    have = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]}
    for loc in locales:
        upsert("appInfoLocalizations", have.get(loc), "appInfo", info["id"], loc,
               {"name": text(loc, "name"), "subtitle": text(loc, "subtitle"), "privacyPolicyUrl": text(loc, "privacy_url")})

    # Age rating: no objectionable content, no web browser, no chat, no gambling, no ads.
    rating = call("GET", f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
    none_enums = ["alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
                  "horrorOrFearThemes", "matureOrSuggestiveThemes", "medicalOrTreatmentInformation",
                  "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
                  "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"]
    false_flags = ["advertising", "ageAssurance", "gambling", "healthOrWellnessTopics", "lootBox", "messagingAndChat",
                   "parentalControls", "socialMedia", "unrestrictedWebAccess", "userGeneratedContent"]
    attrs = {**{k: "NONE" for k in none_enums if k in rating["attributes"]},
             **{k: False for k in false_flags if k in rating["attributes"]}}
    call("PATCH", f"/v1/ageRatingDeclarations/{rating['id']}", {"data": {"type": "ageRatingDeclarations",
                                                                          "id": rating["id"], "attributes": attrs}})
    print("  age rating ✓")

    # The version being prepared: version string, copyright, localized listing, review details, build.
    version = next(v for v in call("GET", f"/v1/apps/{app_id}/appStoreVersions",
                                   params={"filter[platform]": "IOS"})["data"]
                   if v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                                                           "REJECTED", "METADATA_REJECTED"))
    vid = version["id"]
    first = len(call("GET", f"/v1/apps/{app_id}/appStoreVersions")["data"]) == 1
    call("PATCH", f"/v1/appStoreVersions/{vid}", {"data": {"type": "appStoreVersions", "id": vid, "attributes": {
        "versionString": marketing, "copyright": f"{time.gmtime().tm_year} La Crypta"}}})
    print(f"  version {marketing} ✓")
    have = {l["attributes"]["locale"]: l for l in call("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]}
    for loc in locales:
        upsert("appStoreVersionLocalizations", have.get(loc), "appStoreVersion", vid, loc, {
            "description": text(loc, "description"), "keywords": text(loc, "keywords"),
            "promotionalText": text(loc, "promotional_text"), "supportUrl": text(loc, "support_url"),
            "marketingUrl": text(loc, "marketing_url"),
            "whatsNew": None if first else text(loc, "release_notes")})

    review = {"contactFirstName": os.environ.get("REVIEW_FIRST_NAME"), "contactLastName": os.environ.get("REVIEW_LAST_NAME"),
              "contactEmail": os.environ.get("REVIEW_EMAIL"), "contactPhone": os.environ.get("REVIEW_PHONE"),
              "demoAccountRequired": False, "notes": (META / "review_information" / "notes.txt").read_text().strip()}
    review = {k: v for k, v in review.items() if v not in (None, "")}
    existing = call("GET", f"/v1/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
    if not existing and "contactPhone" not in review:
        print("  review details skipped: App Store Connect requires REVIEW_PHONE (+country code)")
    elif existing:
        call("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}",
             {"data": {"type": "appStoreReviewDetails", "id": existing["id"], "attributes": review}})
    else:
        call("POST", "/v1/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": review,
             "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
    if existing or "contactPhone" in review:
        print("  review details ✓")

    if args.screenshots:
        upload_screenshots(vid)

    if args.build:
        build = call("GET", "/v1/builds", params={"filter[app]": app_id, "filter[version]": args.build,
                                                  "filter[processingState]": "VALID"})["data"]
        if not build:
            sys.exit(f"build {args.build} isn't processed (VALID) yet")
        call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": build[0]["id"]}})
        print(f"  build {args.build} attached ✓")


if __name__ == "__main__":
    main()
