//change this when the trace file is changed 1792835
`define traceSize 20


//uncomment below line if you want to see simulation display
`define  DISPLAY             1
`define  DEBUG               1

//change the below parameters for analysis only
`define     NUMTAGTABLES        4   
`define     TABLESIZE           1024
`define     BIMODALSIZE         2048
`define     TAG1_SIZE           8
`define     TAG2_SIZE           9
`define     GHR1                5
`define     GHR2                15
`define     GHR3                44
`define     GHR4                130
`define     BIMODAL_LEN         11
`define     TABLE_LEN           10
`define     PHR_LEN             32

//change the below parameters only if needed, dependent on architecture of TAGE and the design
`define     PC_LEN              64
`define     BIMODAL_CTR_LEN     2
`define     TAGTABLE_CTR_LEN    3
`define     U_LEN               2
`define     OUTCOME             1
`define     PRED                1
`define     GEOM_LEN            32
`define     TARGET_LEN          32