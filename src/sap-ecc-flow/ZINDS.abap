*&---------------------------------------------------------------------*
*& Program     : ZINDS
*& Title       : Daily Stock Loading from ZTBDS Staging Table
*& Author      : (set during activation)
*& Created     : (set during activation)
*& Description : Daily background job that reads all unprocessed records
*&               (ZSTATUS = 'N') from the ZTBDS staging table, assigns
*&               a batch number, and posts initial stock via
*&               BAPI_GOODSMVT_CREATE (movement type 561).
*&               On success: ZSTATUS is set to 'S'.
*&               On error  : ZSTATUS is set to 'E' and a log entry is
*&               written to the ZTBDS_LOG table.
*&               Processing continues for all records even if individual
*&               records fail.
*&               At the end a summary is displayed (ALV or spool list).
*&
*& Prerequisites:
*&   - Tables ZTBDS and ZTBDS_LOG must exist (see table definitions).
*&   - Number range object ZTBDS     (for ZSEQNO in ZFILE_TO_ZTBDS).
*&   - Number range object ZTBDS_LOG (for ZLOGID in ZTBDS_LOG).
*&   - Message class ZZTBDS must exist (SE91).
*&   - Batch classification: ensure batch management is active for
*&     relevant materials (MM02 → Plant data → Batch management).
*&
*& Change Log  :
*& Date        Author      Description
*& ----------- ----------- -------------------------------------------
*&---------------------------------------------------------------------*
REPORT zinds
  NO STANDARD PAGE HEADING
  MESSAGE-ID zztbds.

*----------------------------------------------------------------------*
* INCLUDES (optional – add your organization's standard includes here)
*----------------------------------------------------------------------*

*----------------------------------------------------------------------*
* CONSTANTS
*----------------------------------------------------------------------*
CONSTANTS:
  gc_status_new     TYPE char1   VALUE 'N',
  gc_status_success TYPE char1   VALUE 'S',
  gc_status_error   TYPE char1   VALUE 'E',
  gc_mvt_type       TYPE bwart   VALUE '561',   " Initial stock upload
  gc_mvt_ind        TYPE sobkz   VALUE ' ',      " Unrestricted stock
  gc_log_nr_obj     TYPE inri-nrobj VALUE 'ZTBDS_LOG',
  gc_batch_nr_obj   TYPE inri-nrobj VALUE 'ZTBDS_BATCH'. " Own NR for batch

*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

  PARAMETERS:
    p_test   AS CHECKBOX DEFAULT ' ',   " Test/simulation mode
    p_commit AS CHECKBOX DEFAULT 'X'.   " Auto-commit after each record

SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------*
* DATA DECLARATIONS
*----------------------------------------------------------------------*
" Staging table row type (must match ZTBDS definition)
TYPES:
  BEGIN OF ty_ztbds,
    mandt   TYPE mandt,
    zseqno  TYPE numc10,
    matnr   TYPE matnr,
    werks   TYPE werks_d,
    lgort   TYPE lgort_d,
    charg   TYPE charg_d,
    menge   TYPE meng13,
    meins   TYPE meins,
    zstatus TYPE char1,
    erdat   TYPE erdat,
    erzet   TYPE erzet,
    ernam   TYPE ernam,
  END OF ty_ztbds.

" Log table row type (must match ZTBDS_LOG definition)
TYPES:
  BEGIN OF ty_ztbds_log,
    mandt   TYPE mandt,
    zlogid  TYPE numc10,
    zseqno  TYPE numc10,
    matnr   TYPE matnr,
    charg   TYPE charg_d,
    msgty   TYPE char1,
    msgtx   TYPE char255,
    erdat   TYPE erdat,
    erzet   TYPE erzet,
    ernam   TYPE ernam,
  END OF ty_ztbds_log.

" ALV summary row type
TYPES:
  BEGIN OF ty_summary,
    zseqno  TYPE numc10,
    matnr   TYPE matnr,
    werks   TYPE werks_d,
    lgort   TYPE lgort_d,
    charg   TYPE charg_d,
    menge   TYPE meng13,
    meins   TYPE meins,
    zstatus TYPE char1,
    msgtx   TYPE char255,
  END OF ty_summary.

" Internal tables
DATA:
  gt_ztbds      TYPE TABLE OF ty_ztbds,
  gs_ztbds      TYPE ty_ztbds,
  gs_ztbds_log  TYPE ty_ztbds_log,
  gt_summary    TYPE TABLE OF ty_summary,
  gs_summary    TYPE ty_summary.

" Counters
DATA:
  gv_total    TYPE i,
  gv_success  TYPE i,
  gv_error    TYPE i.

" BAPI structures
DATA:
  gs_goodsmvt_header   TYPE bapi2017_gm_head_01,
  gt_goodsmvt_item     TYPE TABLE OF bapi2017_gm_item_create,
  gs_goodsmvt_item     TYPE bapi2017_gm_item_create,
  gs_goodsmvt_headret       TYPE bapi2017_gm_head_ret,
  gt_goodsmvt_serialnumbers TYPE TABLE OF bapi2017_gm_serialnumber,
  gt_return                 TYPE TABLE OF bapiret2,
  gs_return            TYPE bapiret2.

" Batch number helpers
DATA:
  gv_batch     TYPE charg_d,
  gv_log_nr    TYPE inri-nrlevel,
  gv_batch_nr  TYPE inri-nrlevel.

*----------------------------------------------------------------------*
* START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.

  PERFORM get_unprocessed_records.

  IF gt_ztbds IS INITIAL.
    WRITE: / 'ZINDS: No unprocessed records found in ZTBDS. Exiting.'.
    RETURN.
  ENDIF.

  DESCRIBE TABLE gt_ztbds LINES gv_total.
  WRITE: / |ZINDS: Processing { gv_total } unprocessed records...|.

  LOOP AT gt_ztbds INTO gs_ztbds.

    CLEAR gs_summary.
    gs_summary-zseqno = gs_ztbds-zseqno.
    gs_summary-matnr  = gs_ztbds-matnr.
    gs_summary-werks  = gs_ztbds-werks.
    gs_summary-lgort  = gs_ztbds-lgort.
    gs_summary-menge  = gs_ztbds-menge.
    gs_summary-meins  = gs_ztbds-meins.

    " ----------------------------------------------------------------
    " Step A: Generate / assign batch number
    " ----------------------------------------------------------------
    PERFORM generate_batch_number USING    gs_ztbds
                                   CHANGING gv_batch.
    gs_ztbds-charg   = gv_batch.
    gs_summary-charg = gv_batch.

    " ----------------------------------------------------------------
    " Step B: Post goods movement (initial stock) via BAPI
    " ----------------------------------------------------------------
    PERFORM post_goods_movement USING    gs_ztbds
                                 CHANGING gt_return.

    " ----------------------------------------------------------------
    " Step C: Evaluate BAPI return messages
    " ----------------------------------------------------------------
    PERFORM evaluate_bapi_return USING    gs_ztbds gt_return
                                  CHANGING gs_ztbds-zstatus
                                           gs_summary-msgtx.

    gs_summary-zstatus = gs_ztbds-zstatus.

    " ----------------------------------------------------------------
    " Step D: Update ZTBDS record status
    " ----------------------------------------------------------------
    IF p_test = abap_false.
      PERFORM update_ztbds_status USING gs_ztbds.
    ENDIF.

    " ----------------------------------------------------------------
    " Step E: Write log entry for errors (and optionally successes)
    " ----------------------------------------------------------------
    IF gs_ztbds-zstatus = gc_status_error.
      ADD 1 TO gv_error.
      IF p_test = abap_false.
        PERFORM write_log_entry USING gs_ztbds
                                      gs_summary-msgtx
                                      'E'.
      ENDIF.
    ELSE.
      ADD 1 TO gv_success.
      IF p_test = abap_false.
        PERFORM write_log_entry USING gs_ztbds
                                      gs_summary-msgtx
                                      'S'.
      ENDIF.
    ENDIF.

    APPEND gs_summary TO gt_summary.

  ENDLOOP.

  " ----------------------------------------------------------------
  " Step F: Display ALV summary
  " ----------------------------------------------------------------
  PERFORM display_summary.

*&---------------------------------------------------------------------*
*& Form  GET_UNPROCESSED_RECORDS
*&---------------------------------------------------------------------*
* Selects all ZTBDS records with ZSTATUS = 'N'.
*&---------------------------------------------------------------------*
FORM get_unprocessed_records.

  SELECT *
    FROM ztbds
    INTO TABLE gt_ztbds
   WHERE zstatus = gc_status_new.

  IF sy-subrc <> 0.
    CLEAR gt_ztbds.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form  GENERATE_BATCH_NUMBER
*&---------------------------------------------------------------------*
* Determines the batch number for the record.
* If the staging record already has a batch (CHARG is not initial),
* reuse it; otherwise obtain a new number from a number range.
*
* In a real implementation you may want to call MSC1N (batch create)
* or use classification to set batch characteristics here.
*&---------------------------------------------------------------------*
FORM generate_batch_number USING    is_ztbds   TYPE ty_ztbds
                            CHANGING cv_batch   TYPE charg_d.

  DATA: lv_nr TYPE inri-nrlevel.

  IF is_ztbds-charg IS NOT INITIAL.
    cv_batch = is_ztbds-charg.
    RETURN.
  ENDIF.

  CALL FUNCTION 'NUMBER_GET_NEXT'
    EXPORTING
      nr_range_nr = '01'
      object      = gc_batch_nr_obj
    IMPORTING
      number      = lv_nr
    EXCEPTIONS
      OTHERS      = 1.

  IF sy-subrc = 0.
    " Format as Z + 9-digit zero-padded number, e.g. Z000000001 (10 chars total)
    cv_batch = |Z{ lv_nr WIDTH = 9 ALIGN = RIGHT PAD = '0' }|.
  ELSE.
    " Fallback: use material + date + time as batch
    cv_batch = |{ is_ztbds-matnr(8) }{ sy-datum }|.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form  POST_GOODS_MOVEMENT
*&---------------------------------------------------------------------*
* Calls BAPI_GOODSMVT_CREATE to post the initial stock upload
* (movement type 561 = initial stock entry without reference).
*&---------------------------------------------------------------------*
FORM post_goods_movement USING    is_ztbds  TYPE ty_ztbds
                          CHANGING ct_return TYPE TABLE OF bapiret2.

  CLEAR: gs_goodsmvt_header,
         gt_goodsmvt_item,
         gs_goodsmvt_headret,
         gt_goodsmvt_matdoc,
         ct_return.

  " Fill BAPI header
  gs_goodsmvt_header-pstng_date = sy-datum.
  gs_goodsmvt_header-doc_date   = sy-datum.
  gs_goodsmvt_header-ref_doc_no = is_ztbds-zseqno.  " Reference

  " Fill BAPI item
  CLEAR gs_goodsmvt_item.
  gs_goodsmvt_item-material    = is_ztbds-matnr.
  gs_goodsmvt_item-plant       = is_ztbds-werks.
  gs_goodsmvt_item-stge_loc    = is_ztbds-lgort.
  gs_goodsmvt_item-batch       = is_ztbds-charg.
  gs_goodsmvt_item-entry_qnt   = is_ztbds-menge.
  gs_goodsmvt_item-entry_uom   = is_ztbds-meins.
  gs_goodsmvt_item-move_type   = gc_mvt_type.   " 561
  gs_goodsmvt_item-spec_stock  = gc_mvt_ind.    " Unrestricted

  APPEND gs_goodsmvt_item TO gt_goodsmvt_item.

  IF p_test = abap_true.
    " In test mode, simulate a successful BAPI call without posting
    DATA: ls_ret TYPE bapiret2.
    ls_ret-type    = 'S'.
    ls_ret-message = |TEST MODE – no posting for { is_ztbds-matnr }|.
    APPEND ls_ret TO ct_return.
    RETURN.
  ENDIF.

  CALL FUNCTION 'BAPI_GOODSMVT_CREATE'
    EXPORTING
      goodsmvt_header  = gs_goodsmvt_header
      goodsmvt_code    = '04'           " GM Code for 561 (initial entry)
    IMPORTING
      goodsmvt_headret = gs_goodsmvt_headret
    TABLES
      goodsmvt_item    = gt_goodsmvt_item
      goodsmvt_serialnumbers = gt_goodsmvt_serialnumbers  " pass empty
      return           = ct_return.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form  EVALUATE_BAPI_RETURN
*&---------------------------------------------------------------------*
* Analyses the BAPI return table. If any 'E' or 'A' type message is
* found the status is set to error. Otherwise it commits and sets
* success. The first relevant message text is returned in CV_MSGTX.
*&---------------------------------------------------------------------*
FORM evaluate_bapi_return USING    is_ztbds   TYPE ty_ztbds
                                   it_return  TYPE TABLE OF bapiret2
                           CHANGING cv_status  TYPE char1
                                    cv_msgtx   TYPE char255.

  DATA: ls_ret   TYPE bapiret2,
        lv_error TYPE abap_bool VALUE abap_false.

  CLEAR: cv_status, cv_msgtx.

  LOOP AT it_return INTO ls_ret
    WHERE type = 'E' OR type = 'A'.
    lv_error = abap_true.
    IF cv_msgtx IS INITIAL.
      cv_msgtx = ls_ret-message.
    ENDIF.
  ENDLOOP.

  IF lv_error = abap_true.
    cv_status = gc_status_error.
    CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
  ELSE.
    cv_status = gc_status_success.
    IF p_commit = abap_true.
      CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
        EXPORTING
          wait = 'X'.
    ENDIF.
    " Use the first success message as info text
    READ TABLE it_return INTO ls_ret INDEX 1.
    IF sy-subrc = 0.
      cv_msgtx = ls_ret-message.
    ENDIF.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form  UPDATE_ZTBDS_STATUS
*&---------------------------------------------------------------------*
* Updates the ZSTATUS field in the ZTBDS table for a processed record.
*&---------------------------------------------------------------------*
FORM update_ztbds_status USING is_ztbds TYPE ty_ztbds.

  UPDATE ztbds
     SET zstatus = is_ztbds-zstatus
         charg   = is_ztbds-charg
   WHERE mandt  = sy-mandt
     AND zseqno = is_ztbds-zseqno.

  IF sy-subrc <> 0.
    WRITE: / |Warning: Could not update ZTBDS for ZSEQNO={ is_ztbds-zseqno }|.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form  WRITE_LOG_ENTRY
*&---------------------------------------------------------------------*
* Inserts a new row into ZTBDS_LOG.
* Uses number range ZTBDS_LOG (create in SNRO) for ZLOGID.
*&---------------------------------------------------------------------*
FORM write_log_entry USING is_ztbds  TYPE ty_ztbds
                           iv_msgtx  TYPE char255
                           iv_msgty  TYPE char1.

  DATA: lv_nr TYPE inri-nrlevel.

  CALL FUNCTION 'NUMBER_GET_NEXT'
    EXPORTING
      nr_range_nr = '01'
      object      = gc_log_nr_obj
    IMPORTING
      number      = lv_nr
    EXCEPTIONS
      OTHERS      = 1.

  IF sy-subrc <> 0.
    WRITE: / |Warning: Could not get number range for ZTBDS_LOG|.
    RETURN.
  ENDIF.

  CLEAR gs_ztbds_log.
  gs_ztbds_log-mandt  = sy-mandt.
  gs_ztbds_log-zlogid = lv_nr.
  gs_ztbds_log-zseqno = is_ztbds-zseqno.
  gs_ztbds_log-matnr  = is_ztbds-matnr.
  gs_ztbds_log-charg  = is_ztbds-charg.
  gs_ztbds_log-msgty  = iv_msgty.
  gs_ztbds_log-msgtx  = iv_msgtx.
  gs_ztbds_log-erdat  = sy-datum.
  gs_ztbds_log-erzet  = sy-uzeit.
  gs_ztbds_log-ernam  = sy-uname.

  INSERT ztbds_log FROM gs_ztbds_log.

  IF sy-subrc <> 0.
    WRITE: / |Warning: Could not insert ZTBDS_LOG for ZSEQNO={ is_ztbds-zseqno }|.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form  DISPLAY_SUMMARY
*&---------------------------------------------------------------------*
* Shows a formatted summary of processed records using WRITE statements
* (simple spool output). Replace with ALV (cl_salv_table) if preferred.
*&---------------------------------------------------------------------*
FORM display_summary.

  ULINE.
  WRITE: / 'ZINDS – Processing Summary'.
  ULINE.
  WRITE: / |Run date/time : { sy-datum } / { sy-uzeit }|.
  WRITE: / |User          : { sy-uname }|.
  WRITE: / |Total records : { gv_total }|.
  WRITE: / |Successful    : { gv_success }|.
  WRITE: / |Errors        : { gv_error }|.
  IF p_test = abap_true.
    WRITE: / '*** TEST MODE – no database changes were made ***'.
  ENDIF.
  ULINE.

  " Column headers
  WRITE: / |{ 'Seq No'(001)    WIDTH = 12 }|,
           |{ 'Material'(002)  WIDTH = 20 }|,
           |{ 'Plant'(003)     WIDTH = 6  }|,
           |{ 'SLoc'(004)      WIDTH = 6  }|,
           |{ 'Batch'(005)     WIDTH = 12 }|,
           |{ 'Qty'(006)       WIDTH = 14 }|,
           |{ 'UoM'(007)       WIDTH = 5  }|,
           |{ 'Status'(008)    WIDTH = 8  }|,
           'Message'.
  ULINE.

  LOOP AT gt_summary INTO gs_summary.
    WRITE: / |{ gs_summary-zseqno  WIDTH = 12 }|,
             |{ gs_summary-matnr   WIDTH = 20 }|,
             |{ gs_summary-werks   WIDTH = 6  }|,
             |{ gs_summary-lgort   WIDTH = 6  }|,
             |{ gs_summary-charg   WIDTH = 12 }|,
             |{ gs_summary-menge   WIDTH = 14 }|,
             |{ gs_summary-meins   WIDTH = 5  }|,
             |{ gs_summary-zstatus WIDTH = 8  }|,
             gs_summary-msgtx.

    IF gs_summary-zstatus = gc_status_error.
      FORMAT COLOR COL_NEGATIVE INTENSIFIED ON.
      WRITE: / '  └─ ERROR:', gs_summary-msgtx.
      FORMAT RESET.
    ENDIF.
  ENDLOOP.

  ULINE.

ENDFORM.
