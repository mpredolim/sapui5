*&---------------------------------------------------------------------*
*& ABAP Dictionary Table Definition: ZTBDS
*& Description : Staging table for PowerApp CSV data to be processed
*&               by the daily stock-loading background job (ZINDS).
*&
*& Table Category  : Transparent Table
*& Delivery Class  : A (Application table, master and transaction data)
*& Data Browser    : Display/Maintenance Allowed (SE16 / SM30)
*&---------------------------------------------------------------------*
*
*  To create this table in SAP ECC:
*    Transaction SE11 → Database Table → ZTBDS → Create
*
*  TECHNICAL SETTINGS (SE11 → Technical Settings button):
*    Data Class  : APPL0  (Master data, transparent tables)
*    Size Category : 1   (Estimated number of records up to 100 000)
*    Buffering   : Buffering not allowed
*
*  FIELDS:
*  -----------------------------------------------------------------------
*  Field    Key  Type   Dom/Search Help      Lgth  Dec  Short Description
*  -----------------------------------------------------------------------
*  MANDT     X   CLNT   MANDT                   3    0   Client
*  ZSEQNO    X   NUMC   -                       10   0   Sequence Number (key)
*  MATNR         CHAR   MATNR                   18   0   Material Number
*  WERKS         CHAR   WERKS_D                  4   0   Plant
*  LGORT         CHAR   LGORT_D                  4   0   Storage Location
*  CHARG         CHAR   CHARG_D                 10   0   Batch Number
*  MENGE         QUAN   MENG13                  13   3   Quantity
*  MEINS         UNIT   MEINS                    3   0   Unit of Measure
*  ZSTATUS       CHAR   -                        1   0   Status: N=New, S=Success, E=Error
*  ERDAT         DATS   DATUM                    8   0   Creation Date
*  ERZET         TIMS   UZEIT                    6   0   Creation Time
*  ERNAM         CHAR   USNAM                   12   0   Created By
*  -----------------------------------------------------------------------
*
*  CURRENCY/QUANTITY FIELDS:
*    MENGE references MEINS as its unit field.
*
*  FOREIGN KEYS (recommended):
*    MANDT  → T000-MANDT
*    MATNR  → MARA-MATNR
*    WERKS  → T001W-WERKS
*    WERKS + LGORT → T001L
*
*  SEARCH HELPS:
*    MATNR: Standard search help MARA
*    WERKS: Standard search help WERKS_SH
*
*  INDEX (recommended for performance):
*    Secondary index ZTBDS~ZS01: MANDT + ZSTATUS  (used by ZINDS selection)
*
*&---------------------------------------------------------------------*
*& Data Dictionary source equivalent (DDIC pseudo-code)
*&---------------------------------------------------------------------*

* The following represents the logical structure as it would appear
* in an ABAP TYPE definition (for reference / documentation purposes only).
* Activate this in SE11 – do NOT use ABAP code to create the physical table.

TYPES: BEGIN OF ty_ztbds,
  mandt   TYPE mandt,      " CLNT(3)  – Client (key)
  zseqno  TYPE numc10,     " NUMC(10) – Sequence number (key)
  matnr   TYPE matnr,      " CHAR(18) – Material number
  werks   TYPE werks_d,    " CHAR(4)  – Plant
  lgort   TYPE lgort_d,    " CHAR(4)  – Storage location
  charg   TYPE charg_d,    " CHAR(10) – Batch number
  menge   TYPE meng13,     " QUAN(13,3) – Quantity
  meins   TYPE meins,      " UNIT(3)  – Unit of measure
  zstatus TYPE char1,      " CHAR(1)  – Status: N / S / E
  erdat   TYPE erdat,      " DATS(8)  – Creation date
  erzet   TYPE erzet,      " TIMS(6)  – Creation time
  ernam   TYPE ernam,      " CHAR(12) – Created by
END OF ty_ztbds.

*&---------------------------------------------------------------------*
*& Allowed values for ZSTATUS (implement as Fixed Values in SE11):
*&   'N' – New / Unprocessed
*&   'S' – Successfully processed
*&   'E' – Error during processing
*&---------------------------------------------------------------------*
