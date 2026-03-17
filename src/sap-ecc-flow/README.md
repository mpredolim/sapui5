# SAP ECC Background Processing Flow — PowerApp CSV to Stock Loading

## Overview

This folder contains the ABAP artefacts that implement a complete SAP ECC
background processing flow triggered by a CSV file dropped by a Microsoft
PowerApp onto a SAP application-server directory.

```
Microsoft PowerApp
       │  (writes CSV file)
       ▼
SAP Application Server directory
   /usr/sap/interfaces/powerapp/POWERAPP_INPUT.CSV
       │
       │  [Periodic background job – every 30 min]
       ▼
Program: ZFILE_TO_ZTBDS
  • Reads CSV lines via OPEN DATASET
  • Parses comma-separated fields
  • Inserts records into ZTBDS (ZSTATUS = 'N')
  • Renames / deletes source file to prevent re-processing
       │
       │  [Daily background job]
       ▼
Program: ZINDS
  • Selects ZTBDS records WHERE ZSTATUS = 'N'
  • For each record:
      ├─ Generates a batch number (number range or reuse CHARG)
      ├─ Calls BAPI_GOODSMVT_CREATE (movement type 561)
      ├─ On SUCCESS → ZSTATUS = 'S', writes success log to ZTBDS_LOG
      └─ On ERROR   → ZSTATUS = 'E', writes error log to ZTBDS_LOG
  • Displays ALV / spool summary at the end
```

---

## Files in This Folder

| File | Description |
|---|---|
| `ZTBDS_table_definition.abap` | ABAP Dictionary definition for the ZTBDS staging table |
| `ZTBDS_LOG_table_definition.abap` | ABAP Dictionary definition for the ZTBDS_LOG error log table |
| `ZFILE_TO_ZTBDS.abap` | Report program — periodic file-ingestion background job |
| `ZINDS.abap` | Report program — daily stock-loading background job |
| `README.md` | This document |

---

## Prerequisites

### 1. SAP System Settings

| Item | Action |
|---|---|
| **SAP application-server directory** | Create `/usr/sap/interfaces/powerapp/` on the application server and grant read/write/delete permissions to the `<sapsid>adm` OS user |
| **Authorization object** | Grant `S_DATASET` (authority check on datasets) to the background-job user for the directory path |

### 2. ABAP Dictionary Objects (SE11)

Create both tables in transaction **SE11** before activating the programs:

#### ZTBDS — Staging Table

| Field | Key | Type | Length | Description |
|---|---|---|---|---|
| MANDT | ✓ | CLNT | 3 | Client |
| ZSEQNO | ✓ | NUMC | 10 | Sequence number |
| MATNR | | CHAR | 18 | Material number |
| WERKS | | CHAR | 4 | Plant |
| LGORT | | CHAR | 4 | Storage location |
| CHARG | | CHAR | 10 | Batch number |
| MENGE | | QUAN | 13,3 | Quantity (refs MEINS) |
| MEINS | | UNIT | 3 | Unit of measure |
| ZSTATUS | | CHAR | 1 | Status: N / S / E |
| ERDAT | | DATS | 8 | Creation date |
| ERZET | | TIMS | 6 | Creation time |
| ERNAM | | CHAR | 12 | Created by |

> **Technical Settings:** Data Class = APPL0, Size Category = 1, Buffering = not allowed.
>
> Create a **secondary index** `ZTBDS~ZS01` on `MANDT + ZSTATUS` to speed up the daily selection in ZINDS.

#### ZTBDS_LOG — Error/Audit Log Table

| Field | Key | Type | Length | Description |
|---|---|---|---|---|
| MANDT | ✓ | CLNT | 3 | Client |
| ZLOGID | ✓ | NUMC | 10 | Log ID (from number range) |
| ZSEQNO | | NUMC | 10 | Reference to ZTBDS-ZSEQNO |
| MATNR | | CHAR | 18 | Material number |
| CHARG | | CHAR | 10 | Batch number |
| MSGTY | | CHAR | 1 | Message type: E / S / W / I |
| MSGTX | | CHAR | 255 | Message text |
| ERDAT | | DATS | 8 | Log date |
| ERZET | | TIMS | 6 | Log time |
| ERNAM | | CHAR | 12 | Created by |

> Create a **secondary index** `ZTBDS_LOG~ZS01` on `MANDT + ZSEQNO` for fast lookups.

### 3. Number Range Objects (SNRO)

| Object | Used by | Range | Description |
|---|---|---|---|
| `ZTBDS` | ZFILE_TO_ZTBDS | 01: 0000000001–9999999999 (internal) | ZTBDS sequence numbers |
| `ZTBDS_LOG` | ZINDS | 01: 0000000001–9999999999 (internal) | Log IDs |
| `ZTBDS_BATCH` | ZINDS | 01: 000000001–999999999 (internal) | Auto-generated batch numbers |

### 4. Message Class (SE91)

Create message class **`ZZTBDS`** with at least:

| No. | Text |
|---|---|
| 001 | File read error: & |
| 002 | Database insert error: & |

### 5. ABAP Programs (SE38)

Copy the source code from the `.abap` files in this folder and create the
programs in SE38 (or import via abapGit / transport):

- `ZFILE_TO_ZTBDS`
- `ZINDS`

---

## Background Job Scheduling (SM36)

### Job 1 — Periodic File Check (ZFILE_TO_ZTBDS)

```
Job name   : ZFILE_TO_ZTBDS_JOB
Program    : ZFILE_TO_ZTBDS
Variant    : ZFILE_DEFAULT
  P_PATH   : /usr/sap/interfaces/powerapp/
  P_FILE   : POWERAPP_INPUT.CSV
  P_TEST   : (unchecked)
Schedule   : Periodically, every 30 minutes
Start time : Immediately after saving
User       : BATCH_USER (background user with S_DATASET authorization)
```

Steps in SM36:
1. Transaction **SM36** → Define Background Job
2. Enter Job Name: `ZFILE_TO_ZTBDS_JOB`
3. Step → ABAP Program step → Program: `ZFILE_TO_ZTBDS`, Variant: `ZFILE_DEFAULT`
4. Start Condition → Period: every 30 minutes

### Job 2 — Daily Stock Loading (ZINDS)

```
Job name   : ZINDS_DAILY
Program    : ZINDS
Variant    : ZINDS_DEFAULT
  P_TEST   : (unchecked)
  P_COMMIT : (checked)
Schedule   : Daily at 06:00 (adjust to your business timezone)
User       : BATCH_USER
```

---

## CSV File Format

The PowerApp must write a CSV file with the following structure:

```
MATNR,WERKS,LGORT,CHARG,MENGE,MEINS
MAT-001,1000,0001,,100.000,KG
MAT-002,1000,0001,BATCH-01,50.000,EA
```

- **Row 1**: Header row (skipped automatically by ZFILE_TO_ZTBDS)
- **Rows 2+**: Data rows — 6 comma-separated fields
- `CHARG` may be left blank; ZINDS will generate a batch number automatically
- `MENGE` must use a period as decimal separator
- File encoding: UTF-8 or ISO-8859-1 (match the `ENCODING` option in `OPEN DATASET`)

---

## Directory Configuration

| Parameter | Value | Notes |
|---|---|---|
| Server path | `/usr/sap/interfaces/powerapp/` | Adjust to your landscape |
| Filename | `POWERAPP_INPUT.CSV` | PowerApp must use exactly this name |
| Archive suffix | `_YYYYMMDD_HHMMSS` | Added automatically after processing |
| OS permissions | `rwxr-x---` | `<sapsid>adm` must have read + delete |

The SAP selection-screen parameter `P_PATH` in ZFILE_TO_ZTBDS allows you to
override the path in the job variant without changing the program.

To list accessible directories from within SAP, use transaction **AL11**.

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| CSV file not found | ZFILE_TO_ZTBDS exits silently — no error, no log |
| CSV line has < 6 fields | Line is skipped, error counter incremented, processing continues |
| Number range exhausted | Record skipped, warning written to spool |
| BAPI_GOODSMVT_CREATE error | ZSTATUS = 'E', error logged to ZTBDS_LOG, next record processed |
| DB update of ZTBDS fails | Warning written to spool, processing continues |
| ZTBDS_LOG insert fails | Warning written to spool (non-fatal) |

---

## Monitoring

| Tool | Purpose |
|---|---|
| **SM37** | Monitor background job execution, view spool logs |
| **SE16 / ZTBDS** | Inspect staging table records and their status |
| **SE16 / ZTBDS_LOG** | Review error and success log entries |
| **MB52 / MMBE** | Verify that stock was posted correctly |
| **AL11** | Check SAP application-server directories |

---

## Transport Instructions

1. Create a **Workbench transport** request in SE09/SE10.
2. Add the following objects:
   - `TABL ZTBDS` and `TABL ZTBDS_LOG` (table definitions + indexes)
   - `PROG ZFILE_TO_ZTBDS` and `PROG ZINDS` (programs + variants)
   - `MSAG ZZTBDS` (message class)
   - `NROB ZTBDS`, `NROB ZTBDS_LOG`, `NROB ZTBDS_BATCH` (number range objects — **not** the number range values themselves)
3. Number range **intervals** must be created manually in each target system via SNRO.
4. Background job definitions (SM36) are **not** transported — re-create them in each system.
