# `Tage_predictor.bsv` 
Bluespec System Verilog code documentation of TAgged GEometric (TAGE) History length branch predictor with 5 table predictors (one bimodal table predictor and four tagged table predictors) indexed with Global History Register(GHR) and Path History Register (PHR).

## TAGE Branch Predictor
The inputs and outputs are specified in the interface to the TAGE Predictor hardware:

    interface Tage_predictor_IFC;
        method  Action computePrediction(ProgramCounter pc);  
        method  Action updateTablePred(UpdationPacket upd_pkt);  
        method PredictionPacket output_packet();  
    endinterface

The variables in the TAGE interface is given below:
| Variable Name | Type |Function	 |
|--|--|--|
| `pc` |Input|Program Counter with current branch address  |
|`upd_pkt` | Input | Updation Packet for updating the table predictors |

Methods in the interface of TAGE hardware is given below (#rules) : 

| Method | Type | Function  |
|--|--|--|
| `computePrediction` | Action  | Creates prediction packet after some computations based on TAGE algorithm, current branch address is given as input to the method.  |
| `updateTablePred`  | Action  | Updates the Table predictors based on TAGE algorithm, updation packet is given as input to the method. |
|  `out_packet`  | Value | Outputs the prediction packet after prediction computation. |

## Structures
The following table describes the hardware structure used:
|Structure Name  | Type | Function |
|--|--|--|
| `ghr` | Register | Global History Register internal to the hardware |
| `phr` | Register | Path History Register internal to the hardware |
| `bimodal` | RegFile | Bimodal Table predictor acts as the base/default predictor |
| `table_0` | RegFile | first of four Tagged Table predictors indexed with least long global history|
| `table_1` | RegFile | second of four Tagged Table predictors indexed with longer global history than `table_0` |
| `table_2` | RegFile | third of four Tagged Table predictors indexed with second longest history |
| `table_3` | RegFile | last of four Tagged Table predictors indexed with all of global history |
| `tagTables[4]` | Array | Array of all tagged table predictors grouped together. |
| `pred_pkt` | struct | Stores the fields including prediction and those which are required for updating the corresponding entry in predictor tables at the time of updation |

The following table includes the Wire structure used for passing values between the rules and methods (between hardware structures):
|Wire Name| Function |
|--|--|
|`w_ghr`  | wire to pass GHR value from either rule `rl_spec_update` or `rl_spec_update` to `rl_GHR_PHR_write` rule|
| `w_phr` | wire to pass PHR value from either rule `rl_spec_update` or `rl_spec_update` to `rl_GHR_PHR_write` rule |
| `w_pc` | wire to pass PC value from `computePrediction` method to `rl_spec_update` rule |
| `w_pred` | wire to pass prediction value from `computePrediction` method to `rl_spec_update` rule |
| `w_upd_pkt` | wire to pass updation packet from `updateTablePred` method to `rl_update` rule |
| `w_pred_over` | wire from `computePrediction` to `rl_spec_update` for indicating prediction is over |
| `w_update_over` | wire from `updateTablePred` to `rl_update` for indicating updation is over |

## Rules
The following table shows the rules for updating the GHR and PHR, speculatively as well as non-speculatively:

| Rule Name | Predicate | Function |
|--|--|--|
| `rl_reconstruct_GHR_PHR` | `w_update_over.whas && w_upd_pkt.whas && w_update_over.wget` | Reconstruct PHR and GHR at the time of updation of Table predictors once the actual outcome of branch has obtained |
| `rl_spec_update_GHR_PHR` | `w_pred_over.whas && w_pred.whas && w_pc.whas && w_pred_over.wget` |

## Methods
The three methods based on the TAGE algorithm is described as follows:

#### `computePrediction()` 

This method computes prediction and the associated fields in the prediction packet. This is made available in the next clock cycle through the `out_packet()` method.








