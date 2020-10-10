## `parameter.bsv`

The below table explains the different parameters used in the hardware design files of TAGE, divided into three sections for:

1. Simulations : change the values as per preference
2. Analysis: change the values for different bit sizes
3. Hardware specific: change the values only if needed, dependent on the TAGE architecture



### 1. Simulations

This is for simulations in bluesim using the obtained traces.

| Parameter Name | Function | Usage |
| -------------- | ------------------------------------------------------------ | ------------------------------------- |
| `traceSize`      | Total number of traces (conditional branch instructions) in the trace files. | provide the number of traces as value |
| `DISPLAY` | Displays the simulation result in the terminal | comment if not needed |
| `DEBUG` | For debugging, displays the necessary field values | comment if not needed |

### 2. Analysis

Change the design values as needed.

| Parameter Name | Function                                            | Usage          |
| -------------- | --------------------------------------------------- | -------------- |
| `NUMTAGTABLES`   | Number of Tagged Predictor tables in TAGE structure | Design value : 4 |
| `TABLESIZE` | Size of each Tagged Table predictors | Design value : 1024 |
| `BIMODALSIZE` | Size of Bimodal Table Predictor | Design Value : 1024 |
| `TAG1_SIZE` | Tag lengths of Tagged tables T0 and T1 |Design value : 8|
| `TAG2_SIZE` | Tag lengths of Tagged tables T2 and T3 | Design values : 9|
| `GHR1` | GHR bits accessed by Tagged Table T0 | Design value : 5 |
| `GHR2` | GHR bits accessed by Tagged Table T1 | Design value : 15 |
| `GHR3` | GHR bits accessed by Tagged Table T2 | Design value : 44 |
| `GHR4` | GHR bits accessed by Tagged Table T1 | Design value : 130 |
| `BIMODAL_LEN` | The target bit length of index to access the bimodal table predictor | Design value : 10 (1024) |
| `TABLE_LEN` | The target bit length of index to access the tagged predictor tables | Design value : 10 (1024) |
| `PHR_LEN` | The length of the Path History Register | Design value : 32 |

### 2. Hardware Specific

Change the below parameters only if needed, dependent on the TAGE architecture

| Parameter Name  | Function | Usage |
|---|---|---|
| `PC_LEN` | Number of PC Bits | For 64 bits PC |
| `BIMODAL_CTR_LEN` | Number of bits in Prediction counter of Bimodal Table | Design Value : 2 |
| `TAGTABLE_CTR_LEN` | Number of bits in Prediction Counter of Tagged Table | Design Value : 3|
| `U_LEN` | Number of bits in Usefulness Counter of Tagged Table | Design Value : 2|
| `OUTCOME` | Actual branch outcome, that is 1 bit | Design Value : 1|
| `PRED` | Prediction, that is 1 bit | Design Value : 1|
| `GEOM_LEN` | To specify the integer value for GHR bits | Design Value : 32|
| `TARGET_LEN` | To specify the integer value for Target length bits | Design Value : 32|


