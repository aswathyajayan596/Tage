//SIMULATIONS
//change this when the trace file is changed 
//max no of traces that can be used in simulation : 4294967295 (32b)
`define traceSize 5

//uncomment below line if you want to see simulation display
// `define  DISPLAY             1
// `define  DEBUG               1

//ANALYSIS
//change the below parameters for analysis only
`define     NUMTAGTABLES        4   
`define     TABLESIZE           1024
`define     BIMODALSIZE         1024
`define     TAG1_SIZE           8
`define     TAG2_SIZE           9
`define     GHR1                5
`define     GHR2                15
`define     GHR3                44
`define     GHR4                130
`define     BIMODAL_LEN         10
`define     TABLE_LEN           10
`define     PHR_LEN             32

//HARDWARE SPECIFIC
//change the below parameters only if needed, dependent on architecture of TAGE and the design
`define     PC_LEN              64
`define     BIMODAL_CTR_LEN     2
`define     TAGTABLE_CTR_LEN    3
`define     U_LEN               2
`define     OUTCOME             1
`define     PRED                1
`define     GEOM_LEN            32
`define     TARGET_LEN          32