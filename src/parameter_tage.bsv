//SIMULATIONS
//change this when the trace file is changed 1792835 895842 4184792(present)
`define traceSize 300

//uncomment below line if you want to see simulation display
// `define TAGE_DISPLAY 1
// `define CSR_display 1
// `define DEBUG_1 1
// `define SCRIPT 1

`define ORDER 1


//ANALYSIS
//change the below parameters for analysis only
`define     NUMTAGTABLES        4   
`define     TABLESIZE           1024
`define     BIMODALSIZE         1024
`define     TAG1_CSR1_SIZE      8
`define     TAG1_CSR2_SIZE      7
`define     TAG2_CSR1_SIZE      9
`define     TAG2_CSR2_SIZE      8
`define     GHR1                6
`define     GHR2                16
`define     GHR3                45
`define     GHR4                131
`define     BIMODAL_LEN         9              // 1024 entries
`define     TABLE_LEN           10              // 1024 entries
`define     PHR_LEN             16


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
