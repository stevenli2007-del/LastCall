# LastCall — Devpost Project Story (draft)

> Tagline (one-liner field):
> From one shelf to a network — scan, track, and rescue near-expiry inventory before it's written off.

---

## Inspiration

Walk into any convenience store today and the shelf variety has exploded — and so has the pain of managing expiration dates. For chains like 7-Eleven, quality control is non-negotiable: a single expired product found on the shelf means fines. Yet most small stores still check dates by hand, item by item, which is slow, error-prone, and easy to get wrong when shelves get crowded.

We built LastCall to solve two problems:

1. **Help convenience stores manage their inventory** — know exactly what's on the shelf, where it is, and when it expires, without manual date-checking.
2. **Help stores deal with near-expiry products** — surface items approaching their deadline early enough to sell them at a discount instead of writing them off as waste.

## What it does

LastCall is an iOS app that gives a convenience store a live, expiration-aware map of its shelves:

- **Scan to register**: scan a product's barcode, enter its production date and shelf-life in days — LastCall derives the expiry date automatically.
- **Know where everything is**: each item is recorded with a 3D physical location (container → slot → depth position), so staff can find it without digging through the shelf.
- **Live expiry status**: every item's status (fresh / nearing expiry / expired) is computed in real time from today's date.
- **Scan to remove**: pulling an item off the shelf is verified by scanning its barcode, which archives a removal record and automatically tightens the remaining items' positions in the same slot.

## How we built it

We built LastCall as a fully native iOS app with **SwiftUI + SwiftData + VisionKit + Vision** — five system frameworks, **zero third-party dependencies**.

- Barcode scanning uses Apple's native `DataScannerViewController` (VisionKit), so it works completely offline.
- SwiftData provides local persistence — the entire demo runs in airplane mode.
- All date math uses `Calendar.date(byAdding:)` with start-of-day normalization, so expiry status is correct across time zones and daylight-saving changes.
- Removing an item is a single atomic transaction: write the removal snapshot, delete the item, and shift the depth indices of everything behind it in the same slot — so the shelf map never goes inconsistent.
- We deliberately kept the whole app in just five Swift files, using `// MARK:` sections for navigation.

## Challenges we ran into

- **Barcode scanning**: Safari's `BarcodeDetector` isn't reliably available, so we committed to a native app and Apple's VisionKit stack — which turned out to be fully offline and free.
- **Date correctness**: naive "add 86400 seconds" date math breaks across daylight-saving transitions; we rebuilt all expiry logic on `Calendar` APIs with day-level normalization.
- **Physical-location consistency**: deleting an item mid-slot would orphan the depth indices of items behind it — we designed an invariant set for the shelf data model and enforced it in the removal transaction.
- **Barcode as data**: barcodes like `0641234567` lose leading zeros if stored as numbers — we enforce string storage everywhere.

## Accomplishments that we're proud of

- A complete, working demo running on a real iPhone — scan, register, locate, monitor, and remove products — **entirely offline**.
- **Zero third-party dependencies**: everything is Apple's own frameworks, keeping the app tiny, fast, and auditable.
- A small set of data invariants (documented before we wrote the code) that the shelf model provably maintains, even under mid-slot deletions.

## What we learned

- The hard part of expiry management isn't detecting "expired" — it's keeping the *physical* model (where things actually sit on a shelf) in sync with the digital one.
- Native platform frameworks covered far more than we expected: we never needed a single external package.
- Designing data invariants *before* implementing features saved us from a class of bugs that would have been brutal to debug live.

## What's next for LastCall

- **Ship it on the App Store**, and build out two sides of the product: a **merchant app** and a **consumer app**.
- Every store registered on LastCall gets its own **online storefront**, where it can directly sell its near-expiry products at a discount.
- As more stores join, these storefronts connect into a **network**: a store's "unsellable in time" surplus becomes another neighborhood's half-price aisle — turning food waste into revenue, one last call at a time.
