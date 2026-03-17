*&---------------------------------------------------------------------*
*& ABAP Dictionary Table Definition: ZTBDS_LOG
*& Description : Error / audit log table for records processed by
*&               the daily stock-loading background job (ZINDS).
*&
*& Table Category  : Transparent Table
*& Delivery Class  : A (Application table, master and transaction data)
*& Data Browser    : Display/Maintenance Allowed (SE16 / SM30)
*&---------------------------------------------------------------------*
*
*  To create this table in SAP ECC:
*    Transaction SE11 → Database Table → ZTBDS_LOG → Create
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
*  ZLOGID    X   NUMC   -                       10   0   Log ID (key, from number range)
*  ZSEQNO        NUMC   -                       10   0   Reference to ZTBDS-ZSEQNO
*  MATNR         CHAR   MATNR                   18   0   Material Number
*  CHARG         CHAR   CHARG_D                 10   0   Batch Number
*  MSGTY         CHAR   -                        1   0   Msg type: E=Error, S=Success, W=Warning
*  MSGTX         CHAR   -                      255   0   Message Text
*  ERDAT         DATS   DATUM                    8   0   Log Date
*  ERZET         TIMS   UZEIT                    6   0   Log Time
*  ERNAM         CHAR   USNAM                   12   0   Created By
*  -----------------------------------------------------------------------
*
*  FOREIGN KEYS (recommended):
*    MANDT  → T000-MANDT
*    ZSEQNO → ZTBDS-ZSEQNO  (with check table ZTBDS)
*    MATNR  → MARA-MATNR
*
*  NUMBER RANGE:
*    Create number range object ZTBDS_LOG in transaction SNRO.
*    Internal number range 01: 0000000001 – 9999999999
*    The ZINDS program calls NUMBER_GET_NEXT to obtain ZLOGID values.
*
*  INDEX (recommended for performance):
*    Secondary index ZTBDS_LOG~ZS01: MANDT + ZSEQNO  (lookup by staging record)
*    Secondary index ZTBDS_LOG~ZS02: MANDT + ERDAT   (lookup by date)
*
*&---------------------------------------------------------------------*
*& Data Dictionary source equivalent (DDIC pseudo-code)
*&---------------------------------------------------------------------*

* The following represents the logical structure as it would appear
* in an ABAP TYPE definition (for reference / documentation purposes only).
* Activate this in SE11 – do NOT use ABAP code to create the physical table.

TYPES: BEGIN OF ty_ztbds_log,
  mandt   TYPE mandt,      " CLNT(3)  – Client (key)
  zlogid  TYPE numc10,     " NUMC(10) – Log ID (key)
  zseqno  TYPE numc10,     " NUMC(10) – Reference to ZTBDS-ZSEQNO
  matnr   TYPE matnr,      " CHAR(18) – Material number
  charg   TYPE charg_d,    " CHAR(10) – Batch number
  msgty   TYPE char1,      " CHAR(1)  – Message type: E / S / W
  msgtx   TYPE char255,    " CHAR(255)– Message text
  erdat   TYPE erdat,      " DATS(8)  – Log date
  erzet   TYPE erzet,      " TIMS(6)  – Log time
  ernam   TYPE ernam,      " CHAR(12) – Created by
END OF ty_ztbds_log.

*&---------------------------------------------------------------------*
*& Allowed values for MSGTY (implement as Fixed Values in SE11):
*&   'E' – Error
*&   'S' – Success
*&   'W' – Warning
*&   'I' – Information
*&---------------------------------------------------------------------*
