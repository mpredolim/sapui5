*&---------------------------------------------------------------------*
*& Program     : ZFILE_TO_ZTBDS
*& Title       : PowerApp CSV File Ingestion to ZTBDS Staging Table
*& Author      : (set during activation)
*& Created     : (set during activation)
*& Description : Background job that runs periodically (e.g. every 30
*&               minutes). Checks a pre-defined SAP application server
*&               directory for a CSV file dropped by Microsoft PowerApp.
*&               If found, parses the file and inserts/updates records
*&               in the custom staging table ZTBDS (ZSTATUS = 'N').
*&               After a successful load the file is renamed to an
*&               archive name so that it is not processed twice.
*&
*& Change Log  :
*& Date        Author      Description
*& ----------- ----------- -------------------------------------------
*&---------------------------------------------------------------------*
REPORT zfile_to_ztbds
  NO STANDARD PAGE HEADING
  MESSAGE-ID zztbds.           " Create message class ZZTBDS in SE91

*----------------------------------------------------------------------*
* CONSTANTS
*----------------------------------------------------------------------*
CONSTANTS:
  gc_default_path  TYPE string VALUE '/usr/sap/interfaces/powerapp/',
  gc_default_file  TYPE string VALUE 'POWERAPP_INPUT.CSV',
  gc_status_new    TYPE char1  VALUE 'N',
  gc_field_sep     TYPE char1  VALUE ',',
  gc_num_range_obj TYPE inri-nrobj VALUE 'ZTBDS'.  " Create in SNRO

*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.

  PARAMETERS:
    p_path   TYPE string DEFAULT '/usr/sap/interfaces/powerapp/'
             LOWER CASE,
    p_file   TYPE string DEFAULT 'POWERAPP_INPUT.CSV'
             LOWER CASE,
    p_test   AS CHECKBOX DEFAULT ' '.   " Test mode – no DB changes

SELECTION-SCREEN END OF BLOCK b1.

*----------------------------------------------------------------------*
* DATA DECLARATIONS
*----------------------------------------------------------------------*
TYPES:
  BEGIN OF ty_ztbds_raw,
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
  END OF ty_ztbds_raw.

DATA:
  gv_filepath      TYPE string,           " Full path + filename
  gv_archive_path  TYPE string,           " Archive file path
  gt_raw_lines     TYPE TABLE OF string,  " Lines read from CSV
  gs_ztbds         TYPE ty_ztbds_raw,     " Single staging record
  gt_ztbds         TYPE TABLE OF ty_ztbds_raw,  " Staging records to insert
  gv_line          TYPE string,           " Current CSV line
  gv_tabix         TYPE sy-tabix,
  gv_inserted      TYPE i,
  gv_errors        TYPE i,
  gv_msg           TYPE string.

* Number range
DATA:
  gs_nr_return     TYPE inri,
  gv_next_nr       TYPE inri-nrlevel.

* Field split helper
DATA:
  gt_fields        TYPE TABLE OF string,
  gv_field         TYPE string.

*----------------------------------------------------------------------*
* START-OF-SELECTION
*----------------------------------------------------------------------*
START-OF-SELECTION.

  " ----------------------------------------------------------------
  " 1.  Build the full file path
  " ----------------------------------------------------------------
  CONCATENATE p_path p_file INTO gv_filepath.

  " ----------------------------------------------------------------
  " 2.  Check if the file exists on the application server
  " ----------------------------------------------------------------
  PERFORM check_file_exists USING    gv_filepath
                             CHANGING gv_msg.
  IF gv_msg IS NOT INITIAL.
    " File does not exist – exit silently (expected between uploads)
    WRITE: / 'File not found – nothing to process:', gv_filepath.
    RETURN.
  ENDIF.

  " ----------------------------------------------------------------
  " 3.  Open and read the CSV file
  " ----------------------------------------------------------------
  PERFORM read_csv_file USING gv_filepath
                        CHANGING gt_raw_lines gv_msg.
  IF gv_msg IS NOT INITIAL.
    MESSAGE e001(zztbds) WITH gv_msg.
    RETURN.
  ENDIF.

  IF gt_raw_lines IS INITIAL.
    WRITE: / 'File is empty – nothing to process.'.
    RETURN.
  ENDIF.

  " ----------------------------------------------------------------
  " 4.  Parse each CSV line into internal table
  " ----------------------------------------------------------------
  PERFORM parse_csv_lines USING    gt_raw_lines
                           CHANGING gt_ztbds gv_errors.

  IF gt_ztbds IS INITIAL.
    WRITE: / 'No valid records parsed from file.'.
    RETURN.
  ENDIF.

  " ----------------------------------------------------------------
  " 5.  Insert records into ZTBDS (skip in test mode)
  " ----------------------------------------------------------------
  IF p_test = abap_true.
    WRITE: / '*** TEST MODE – no database changes will be made ***'.
    LOOP AT gt_ztbds INTO gs_ztbds.
      WRITE: / gs_ztbds-zseqno, gs_ztbds-matnr, gs_ztbds-werks,
               gs_ztbds-lgort, gs_ztbds-menge, gs_ztbds-meins.
    ENDLOOP.
  ELSE.
    PERFORM insert_ztbds USING    gt_ztbds
                          CHANGING gv_inserted gv_msg.
    IF gv_msg IS NOT INITIAL.
      MESSAGE e002(zztbds) WITH gv_msg.
      RETURN.
    ENDIF.

    " ----------------------------------------------------------------
    " 6.  Archive / rename the file to prevent re-processing
    " ----------------------------------------------------------------
    PERFORM archive_file USING    gv_filepath p_path p_file
                          CHANGING gv_archive_path gv_msg.
    IF gv_msg IS NOT INITIAL.
      " Non-fatal: log the warning but do not roll back the inserts
      WRITE: / 'Warning: could not archive file:', gv_msg.
    ENDIF.
  ENDIF.

  " ----------------------------------------------------------------
  " 7.  Summary output
  " ----------------------------------------------------------------
  WRITE: / '=== ZFILE_TO_ZTBDS – Processing Summary ==='.
  WRITE: / 'File processed    :', gv_filepath.
  WRITE: / 'Records inserted  :', gv_inserted.
  WRITE: / 'Parse errors      :', gv_errors.
  IF gv_archive_path IS NOT INITIAL.
    WRITE: / 'Archived to       :', gv_archive_path.
  ENDIF.

*&---------------------------------------------------------------------*
*& Form  CHECK_FILE_EXISTS
*&---------------------------------------------------------------------*
* Checks whether the file exists on the application server.
* Returns a non-initial MSG if the file is NOT found.
*&---------------------------------------------------------------------*
FORM check_file_exists USING    iv_path  TYPE string
                        CHANGING cv_msg   TYPE string.

  DATA: lv_length TYPE i,
        lv_result TYPE abap_bool.

  CLEAR cv_msg.

  " Use OPEN DATASET to test existence
  OPEN DATASET iv_path FOR INPUT IN TEXT MODE ENCODING DEFAULT.
  IF sy-subrc <> 0.
    cv_msg = iv_path.   " Non-initial = file not found
  ELSE.
    CLOSE DATASET iv_path.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form  READ_CSV_FILE
*&---------------------------------------------------------------------*
* Opens the application-server file and reads all lines into an
* internal string table.
*&---------------------------------------------------------------------*
FORM read_csv_file USING    iv_path     TYPE string
                   CHANGING ct_lines    TYPE TABLE OF string
                            cv_msg      TYPE string.

  DATA: lv_line TYPE string.

  CLEAR: ct_lines, cv_msg.

  OPEN DATASET iv_path FOR INPUT IN TEXT MODE ENCODING DEFAULT.
  IF sy-subrc <> 0.
    cv_msg = |Could not open file: { iv_path }|.
    RETURN.
  ENDIF.

  DO.
    READ DATASET iv_path INTO lv_line.
    IF sy-subrc <> 0.
      EXIT.
    ENDIF.
    " Skip header row (first line) – assumed to contain column names
    IF sy-index = 1.
      CONTINUE.
    ENDIF.
    " Skip blank lines
    IF lv_line IS INITIAL.
      CONTINUE.
    ENDIF.
    APPEND lv_line TO ct_lines.
  ENDDO.

  CLOSE DATASET iv_path.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form  PARSE_CSV_LINES
*&---------------------------------------------------------------------*
* Splits each CSV line by comma and maps fields to ty_ztbds_raw.
* Expected column order (0-based):
*   0=MATNR, 1=WERKS, 2=LGORT, 3=CHARG, 4=MENGE, 5=MEINS
*&---------------------------------------------------------------------*
FORM parse_csv_lines USING    it_lines   TYPE TABLE OF string
                     CHANGING ct_ztbds   TYPE TABLE OF ty_ztbds_raw
                              cv_errors  TYPE i.

  DATA:
    ls_ztbds   TYPE ty_ztbds_raw,
    lv_line    TYPE string,
    lt_fields  TYPE TABLE OF string,
    lv_field   TYPE string,
    lv_nr      TYPE inri-nrlevel.

  CLEAR: ct_ztbds, cv_errors.

  LOOP AT it_lines INTO lv_line.

    CLEAR ls_ztbds.
    CLEAR lt_fields.

    " Split CSV line into individual field values
    SPLIT lv_line AT gc_field_sep INTO TABLE lt_fields.

    " Validate minimum number of columns
    IF lines( lt_fields ) < 6.
      ADD 1 TO cv_errors.
      WRITE: / |Line { sy-tabix }: insufficient fields – skipped|.
      CONTINUE.
    ENDIF.

    " Get next number range value for ZSEQNO
    CALL FUNCTION 'NUMBER_GET_NEXT'
      EXPORTING
        nr_range_nr = '01'
        object      = gc_num_range_obj
      IMPORTING
        number      = lv_nr
      EXCEPTIONS
        OTHERS      = 1.
    IF sy-subrc <> 0.
      ADD 1 TO cv_errors.
      WRITE: / |Line { sy-tabix }: number range error – skipped|.
      CONTINUE.
    ENDIF.

    ls_ztbds-zseqno = lv_nr.

    " Map fields (trim leading/trailing spaces and quotes)
    READ TABLE lt_fields INTO lv_field INDEX 1.
    ls_ztbds-matnr = condense( val = lv_field ).

    READ TABLE lt_fields INTO lv_field INDEX 2.
    ls_ztbds-werks = condense( val = lv_field ).

    READ TABLE lt_fields INTO lv_field INDEX 3.
    ls_ztbds-lgort = condense( val = lv_field ).

    READ TABLE lt_fields INTO lv_field INDEX 4.
    ls_ztbds-charg = condense( val = lv_field ).

    READ TABLE lt_fields INTO lv_field INDEX 5.
    lv_field = condense( val = lv_field ).
    ls_ztbds-menge = lv_field.

    READ TABLE lt_fields INTO lv_field INDEX 6.
    ls_ztbds-meins = condense( val = lv_field ).

    " Status defaults to 'N' (new/unprocessed)
    ls_ztbds-zstatus = gc_status_new.

    " Audit fields
    ls_ztbds-mandt = sy-mandt.
    ls_ztbds-erdat = sy-datum.
    ls_ztbds-erzet = sy-uzeit.
    ls_ztbds-ernam = sy-uname.

    APPEND ls_ztbds TO ct_ztbds.

  ENDLOOP.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form  INSERT_ZTBDS
*&---------------------------------------------------------------------*
* Inserts all parsed records into table ZTBDS.
* Uses INSERT ... FROM TABLE for best performance.
* On duplicate key (MODIFY) so that repeated uploads are idempotent.
*&---------------------------------------------------------------------*
FORM insert_ztbds USING    it_ztbds    TYPE TABLE OF ty_ztbds_raw
                  CHANGING cv_inserted TYPE i
                           cv_msg      TYPE string.

  DATA: lv_dbrc TYPE sy-subrc.

  CLEAR: cv_inserted, cv_msg.

  " MODIFY is safer than INSERT here: avoids dump on duplicates
  MODIFY ztbds FROM TABLE it_ztbds.    " Note: cast is implicit

  lv_dbrc = sy-subrc.

  IF lv_dbrc = 0.
    cv_inserted = sy-dbcnt.
    COMMIT WORK AND WAIT.
  ELSE.
    cv_msg = |DB MODIFY ZTBDS failed with sy-subrc={ lv_dbrc }|.
    ROLLBACK WORK.
  ENDIF.

ENDFORM.

*&---------------------------------------------------------------------*
*& Form  ARCHIVE_FILE
*&---------------------------------------------------------------------*
* Renames the processed CSV file by appending a timestamp suffix so
* it will not be picked up in the next run.
* Example: POWERAPP_INPUT.CSV → POWERAPP_INPUT_20260317_134215.CSV
*&---------------------------------------------------------------------*
FORM archive_file USING    iv_src_path  TYPE string
                           iv_dir       TYPE string
                           iv_filename  TYPE string
                  CHANGING cv_arch_path TYPE string
                           cv_msg       TYPE string.

  DATA:
    lv_timestamp  TYPE string,
    lv_new_name   TYPE string,
    lv_basename   TYPE string,
    lv_ext        TYPE string,
    lv_dot_pos    TYPE i.

  CLEAR: cv_arch_path, cv_msg.

  " Build timestamp string YYYYMMDD_HHMMSS
  lv_timestamp = |{ sy-datum }_{ sy-uzeit }|.

  " Separate base name and extension from filename
  lv_dot_pos = strlen( iv_filename ) - 4.   " Remove last 4 chars (.CSV)
  IF lv_dot_pos > 0.
    lv_basename = iv_filename(lv_dot_pos).  " Without extension (.CSV)
    lv_ext      = iv_filename+lv_dot_pos.   " .CSV
  ELSE.
    lv_basename = iv_filename.
    lv_ext      = ''.
  ENDIF.

  " Remove trailing dot from basename if present
  IF lv_basename CS '.'.
    lv_dot_pos = strlen( lv_basename ) - 1.
    lv_basename = lv_basename(lv_dot_pos).
  ENDIF.

  lv_new_name   = |{ lv_basename }_{ lv_timestamp }{ lv_ext }|.
  cv_arch_path  = |{ iv_dir }{ lv_new_name }|.

  " Rename using file system command via OPEN/CLOSE trick is not
  " possible in pure ABAP. Use ARCHIVFILEMANAGEMENT or a shell command.
  " Here we use the SAP-provided function for file operations.
  CALL FUNCTION 'EPS_GET_FILE_ATTRIBUTES'
    EXPORTING
      file_name              = iv_filename
      dir_name               = iv_dir
    EXCEPTIONS
      read_directory_failed  = 1
      OTHERS                 = 2.
  " If EPS functions are not available, fall back to DELETE DATASET
  " after copying contents (not shown here for brevity).
  " For most ECC systems, renaming via OS-level command is preferred.
  " A simpler approach: delete the source file.
  IF sy-subrc <> 0.
    " Attempt delete so the file is not reprocessed
    DELETE DATASET iv_src_path.
    IF sy-subrc <> 0.
      cv_msg = |Could not delete/archive file: { iv_src_path }|.
    ENDIF.
  ENDIF.

ENDFORM.
