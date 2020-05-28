FUNCTION ZK_RFC_READ_TABLE_V2 .
*"----------------------------------------------------------------------
*"*"Local Interface:
*"  IMPORTING
*"     VALUE(QUERY_TABLE) LIKE  DD02L-TABNAME
*"     VALUE(DELIMITER) LIKE  SONV-FLAG DEFAULT SPACE
*"     VALUE(NO_DATA) LIKE  SONV-FLAG DEFAULT SPACE
*"     VALUE(ROWSKIPS) TYPE  /BI0/OIUOMZ1F OPTIONAL
*"     VALUE(ROWCOUNT) TYPE  /BI0/OIUOMZ1F OPTIONAL
*"  TABLES
*"      FIELDS STRUCTURE  RFC_DB_FLD
*"      DATA STRUCTURE  CHAR8000
*"      OPTIONS2 STRUCTURE  ZKK_CHAR30000
*"  EXCEPTIONS
*"      TABLE_NOT_AVAILABLE
*"      TABLE_WITHOUT_DATA
*"      OPTION_NOT_VALID
*"      FIELD_NOT_VALID
*"      NOT_AUTHORIZED
*"      DATA_BUFFER_EXCEEDED
*"----------------------------------------------------------------------
"

CALL FUNCTION 'VIEW_AUTHORITY_CHECK'
     EXPORTING
          VIEW_ACTION                    = 'S'
          VIEW_NAME                      = QUERY_TABLE
     EXCEPTIONS
          NO_AUTHORITY                   = 2
          NO_CLIENTINDEPENDENT_AUTHORITY = 2
          NO_LINEDEPENDENT_AUTHORITY     = 2
          OTHERS                         = 1.

IF SY-SUBRC = 2.
  RAISE NOT_AUTHORIZED.
ELSEIF SY-SUBRC = 1.
  RAISE TABLE_NOT_AVAILABLE.
ENDIF.

* ----------------------------------------------------------------------
*  find out about the structure of QUERY_TABLE
* ----------------------------------------------------------------------
DATA BEGIN OF TABLE_STRUCTURE OCCURS 10.
        INCLUDE STRUCTURE DFIES.
DATA END OF TABLE_STRUCTURE.
"DATA TABLE_HEADER LIKE X030L.
DATA TABLE_TYPE TYPE DD02V-TABCLASS.


CALL FUNCTION 'DDIF_FIELDINFO_GET'
  EXPORTING
    TABNAME              = QUERY_TABLE
*   FIELDNAME            = ' '
*   LANGU                = SY-LANGU
*   LFIELDNAME           = ' '
*   ALL_TYPES            = ' '
*   GROUP_NAMES          = ' '
  IMPORTING
*   X030L_WA             =
    DDOBJTYPE            = TABLE_TYPE
*   DFIES_WA             =
*   LINES_DESCR          =
  TABLES
    DFIES_TAB            = TABLE_STRUCTURE
*   FIXED_VALUES         =
  EXCEPTIONS
    NOT_FOUND            = 1
    INTERNAL_ERROR       = 2
    OTHERS               = 3
          .
IF SY-SUBRC <> 0.
  RAISE TABLE_NOT_AVAILABLE.
ENDIF.
IF TABLE_TYPE = 'INTTAB'.
  RAISE TABLE_WITHOUT_DATA.
ENDIF.

* ----------------------------------------------------------------------
*  isolate first field of DATA as output field
*  (i.e. allow for changes to structure DATA!)
* ----------------------------------------------------------------------
DATA LINE_LENGTH TYPE I.
FIELD-SYMBOLS <D>.
ASSIGN COMPONENT 0 OF STRUCTURE DATA TO <D>.
DESCRIBE FIELD <D> LENGTH LINE_LENGTH in character mode.

* ----------------------------------------------------------------------
*  if FIELDS are not specified, read all available fields
* นับจำนวน Filed
* ----------------------------------------------------------------------

DATA NUMBER_OF_FIELDS TYPE I.
DESCRIBE TABLE FIELDS LINES NUMBER_OF_FIELDS.
IF NUMBER_OF_FIELDS = 0.
  LOOP AT TABLE_STRUCTURE.
    MOVE TABLE_STRUCTURE-FIELDNAME TO FIELDS-FIELDNAME.
    APPEND FIELDS.
  ENDLOOP.
ENDIF.
* ----------------------------------------------------------------------
*  for each field which has to be read, copy structure information
*  into tables FIELDS_INT (internal use) and FIELDS (output)
* ----------------------------------------------------------------------
DATA: BEGIN OF FIELDS_INT OCCURS 10,
        FIELDNAME  LIKE TABLE_STRUCTURE-FIELDNAME,
        TYPE       LIKE TABLE_STRUCTURE-INTTYPE,
        DECIMALS   LIKE TABLE_STRUCTURE-DECIMALS,
        LENGTH_SRC LIKE TABLE_STRUCTURE-INTLEN,
        LENGTH_DST LIKE TABLE_STRUCTURE-LENG,
        OFFSET_SRC LIKE TABLE_STRUCTURE-OFFSET,
        OFFSET_DST LIKE TABLE_STRUCTURE-OFFSET,
      END OF FIELDS_INT,
      LINE_CURSOR TYPE I.

LINE_CURSOR = 0.
*  for each field which has to be read ...
LOOP AT FIELDS.

  READ TABLE TABLE_STRUCTURE WITH KEY FIELDNAME = FIELDS-FIELDNAME.
  IF SY-SUBRC NE 0.
    RAISE FIELD_NOT_VALID.
  ENDIF.

* compute the place for field contents in DATA rows:
* if not first field in row, allow space for delimiter
  IF LINE_CURSOR <> 0.
    IF NO_DATA EQ SPACE AND DELIMITER NE SPACE.
      LINE_CURSOR = LINE_CURSOR + 1. "SARMA
      MOVE DELIMITER TO DATA+LINE_CURSOR .
    ENDIF.
    LINE_CURSOR = LINE_CURSOR + STRLEN( DELIMITER ).
  ENDIF.

* ... copy structure information into tables FIELDS_INT
* (which is used internally during SELECT) ...
  FIELDS_INT-FIELDNAME  = TABLE_STRUCTURE-FIELDNAME.
  FIELDS_INT-LENGTH_SRC = TABLE_STRUCTURE-INTLEN .
  FIELDS_INT-LENGTH_DST = TABLE_STRUCTURE-LENG  .
  FIELDS_INT-OFFSET_SRC = TABLE_STRUCTURE-OFFSET .
  FIELDS_INT-OFFSET_DST = LINE_CURSOR .
  FIELDS_INT-TYPE       = TABLE_STRUCTURE-INTTYPE.
  FIELDS_INT-DECIMALS   = TABLE_STRUCTURE-DECIMALS.
* compute the place for contents of next field in DATA rows
  LINE_CURSOR = LINE_CURSOR + TABLE_STRUCTURE-LENG.
  IF LINE_CURSOR > LINE_LENGTH AND NO_DATA EQ SPACE.
    RAISE DATA_BUFFER_EXCEEDED.
  ENDIF.
  APPEND FIELDS_INT.

* ... and into table FIELDS (which is output to the caller)
  FIELDS-FIELDTEXT = TABLE_STRUCTURE-FIELDTEXT.
  FIELDS-TYPE      = TABLE_STRUCTURE-INTTYPE.
  FIELDS-LENGTH    = FIELDS_INT-LENGTH_DST + 2 .
  FIELDS-OFFSET    = FIELDS_INT-OFFSET_DST + 2.
  MODIFY FIELDS.

ENDLOOP.
* end of loop at FIELDS

* ----------------------------------------------------------------------
*  read data from the database and copy relevant portions into DATA
* ----------------------------------------------------------------------
* output data only if NO_DATA equals space (otherwise the structure
* information in FIELDS is the only result of the module)
IF NO_DATA EQ SPACE.

DATA: BEGIN OF WORK, BUFFER(30000), END OF WORK.

FIELD-SYMBOLS: <WA> TYPE ANY, <COMP> TYPE ANY.
 " --- begin of modification
 " ASSIGN WORK TO <WA> CASTING TYPE (QUERY_TABLE).
 DATA: tab_ref TYPE REF TO data.
 CREATE DATA tab_ref TYPE (query_table).
 ASSIGN  tab_ref->* TO <wa>.
 " --- end of modification
IF ROWCOUNT > 0.
  ROWCOUNT = ROWCOUNT + ROWSKIPS.
ENDIF.

data : NoRunRow type /BI0/OIUOMZ1F.
NoRunRow = 1. " ใช้แทน  SY-DBCNT เพื่อนับจำนวน Row
SELECT * FROM (QUERY_TABLE) INTO <WA> WHERE (OPTIONS2).
    "NoRunRow = NoRunRow .
    IF NoRunRow GT ROWSKIPS. " เก็บข้อมูลก็ต่อเมื่อ ถึง Row ที่ มากกว่า ROWSKIPS , ใช้ SY-DBCNT=>NoRunRow

*   copy all relevant fields into DATA (output) table
      LOOP AT FIELDS_INT.
        IF FIELDS_INT-TYPE = 'P'.
        ASSIGN COMPONENT FIELDS_INT-FIELDNAME
            OF STRUCTURE <WA> TO <COMP>
           TYPE FIELDS_INT-TYPE
            DECIMALS FIELDS_INT-DECIMALS.
        ELSE.
        ASSIGN COMPONENT FIELDS_INT-FIELDNAME
            OF STRUCTURE <WA> TO <COMP>
            TYPE     FIELDS_INT-TYPE.
            ENDIF.
            MOVE <COMP> TO
            <D>+FIELDS_INT-OFFSET_DST(FIELDS_INT-LENGTH_DST).
      ENDLOOP.
*   end of loop at FIELDS_INT
      APPEND DATA.
      IF ROWCOUNT > 0 AND NoRunRow GE ROWCOUNT. EXIT. ENDIF. "ออกเมื่อ ถึง Row สุดท้ายที่ต้องการ

    ENDIF.
    NoRunRow = NoRunRow + 1 .
  ENDSELECT.

ENDIF.

ENDFUNCTION.

*######################################################################
*##   How To USe
*######################################################################
*DATA: lt_options TYPE TABLE OF rfc_db_opt,
*        lt_fields  TYPE TABLE OF rfc_db_fld,
*        lt_entries TYPE TABLE OF CHAR8000"dpr_pha_type.
*        ,line like line of lt_entries.
*
*CALL FUNCTION 'ZK_RFC_READ_TABLE'
*  EXPORTING
*    query_table = 'MARA'
*    DELIMITER = '|'
*  TABLES
*    options     = lt_options
*    fields      = lt_fields
*    data        = lt_entries.
*
*loop at lt_entries into line.
*  write : /
*            line-FELD.
*
*endloop.