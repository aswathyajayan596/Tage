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

Methods in the interface of TAGE hardware is given below : 

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
| `rl_spec_update_GHR_PHR` | `w_pred_over.whas && w_pred.whas && w_pc.whas && w_pred_over.wget` |Rule to speculatively update GHR and PHR once prediction is made.|
| `rl_GHR_PHR_write`|	| Rule to write to internal GHR and PHR at both speculation as well as reconstruction	|

## Methods
The three methods based on the TAGE algorithm is described as follows:

### 1. `computePrediction() `

This method computes prediction and the associated fields in the prediction packet. This is made available in the next clock cycle through the `out_packet()` method.

| Variable Name | Type | Function |
| ------------- | ---- | -------- |
| `computedTag[4]` | Array of Type `Tag` with size 4 | temporarily stores the computed tags using Tag Function for each Tagged table predictors |
| `bimodal_index` | `BimodalIndex` type | temporarily stores the computed index for Bimodal Predictor table using index function |
| `tagTable_index[4]` | Array of Type `TagTableIndex` with size 4 | temporarily stores the computed index for each Tagged table predictors using Index function |
| `t_pred_pkt` | `PredictionPacket` | Stores the prediction packet temporarily, for writing to `pred_pkt` register |
| `t_pred_pkt.phr` | `PathHistory` | temporarily stores the PHR in the field of prediction packet |
| `matched` | `Bool` | True if there is a tag match in entry from which prediction is considered, False if there is no tag match |
| `altMatched` | `Bool` | True if there is a tag match in entry from which alternate prediction is considered, False if there is no tag match |

The below code updates the PHR value in temporary `pred_pkt` as soon as the `pc` value is obtained:

```
t_pred_pkt.phr = update_PHR(phr, pc);
```

The update_PHR function takes care of the updation of PHR by taking in value from internal PHR and input PC.

#### Indexing and Tagging

`bimodal_index` is computed and assigned to bimodal_index field in `t_pred_pkt`. The code block is as given below:

    bimodal_index = truncate(computeIndex(pc,ghr,t_pred_pkt.phr,3'b000));
    t_pred_pkt.bimodal_index = bimodal_index;
For each `tagTable_index`, the code block is as shown below:

```
for (Integer i = 0; i < 4; i=i+1) begin
	TableNo tNo = fromInteger(i+1);
    tagTable_index[i] = truncate(computeIndex(pc,ghr,t_pred_pkt.phr,tNo));
    t_pred_pkt.tagTable_index[i] = tagTable_index[i];
    if(i<2) begin
    	computedTag[i] = tagged Tag1 truncate(computeTag(pc,ghr,tNo));
        t_pred_pkt.tableTag[i] = computedTag[i];
    end
    else begin
    	computedTag[i] = tagged Tag2 truncate(computeTag(pc,ghr,tNo));
        t_pred_pkt.tableTag[i] = computedTag[i];
    end
end
```

Based on the table number of Tables, the tags are assigned. For tables with table number, greater than or equal to 2, Tag2 is assigned. For tables with table number, less than 2, Tag1 is assigned. (The keyword `Tagged` is used, since Tag is Union Type.)

#### Check for Tag Match

Initialised the bimodal table predictor as the default predictor as per the algorithm. 

Corresponding fields in `t_pred_pkt` is set according to the bimodal table predictor. The index from which the access should happen has been calculated as per the previous section. As shown below:

    t_pred_pkt.tableNo = 3'b000;
    t_pred_pkt.altpred = bimodal.sub(bimodal_index).ctr[1];
    t_pred_pkt.pred = bimodal.sub(bimodal_index).ctr[1];
    t_pred_pkt.ctr[0] = zeroExtend(bimodal.sub(bimodal_index).ctr);

Also, `matched` and `altMatched` are initialised to `False`, indicating that there has been no tag match and prediction is done by the bimodal table predictor. As shown below:

    Bool matched = False;
    Bool altMatched = False;
Now, for each tagged table predictors iterated from T4 to T0 (from longer history table to shorter history table), once there is tag match from the calculated index as per the previous section, that table entry is considered and updated in the `t_pred_pkt` fields. In such a case, `matched` will be updated to `True`. 

Once `matched` becomes `True`, the second longest history where there is a tag match is considered as alternate prediction. In that case, `altMatched` becomes `True`.

The code is as shown below:

    for (Integer i = 3; i >= 0; i=i-1) begin
    	if(tagTables[i].sub(tagTable_index[i]).tag == computedTag[i] && !matched) begin
    		t_pred_pkt.ctr[i+1] = tagTables[i].sub(tagTable_index[i]).ctr;
        	t_pred_pkt.pred = tagTables[i].sub(tagTable_index[i]).ctr[2];
        	t_pred_pkt.tableNo = fromInteger(i+1); 
        	t_pred_pkt.uCtr[i] = tagTables[i].sub(tagTable_index[i]).uCtr;     matched = True;
    	end
        else if(tagTables[i].sub(tagTable_index[i]).tag == computedTag[i] && matched && !altMatched) begin
        	t_pred_pkt.altpred = tagTables[i].sub(tagTable_index[i]).ctr[2];
            altMatched = True;
        end
    end
The below code is for setting the corresponding wires to rule `rl_spec_update_GHR_PHR` for speculatively updating the internal GHR and PHR in the TAGE hardware:

```
w_pred <= t_pred_pkt.pred;              
w_pc <= pc;
```

Speculative updation of GHR in temporary prediction packet by calling `update_GHR` function after obtaining prediction from tag matched entry.

```
t_pred_pkt.ghr = update_GHR(ghr, t_pred_pkt.pred);
```

Assigning into Register `pred_pkt` with variable `t_pred_pkt` for it to appear between methods:  

```
pred_pkt <= t_pred_pkt;
```

Also, as prediction is over:

```
w_pred_over <= True;
```

This enables the `rl_spec_update_GHR_PHR`.

### 2. `updateTablePred()`

`upd_pkt` of `UpdationPacket`type is made available as input to the TAGE predictor once the Actual outcome of the corresponding branch is available. The actual outcome and misprediction bit is made available in the Updation Packet ( for simulation purpose, the testbench does this function).

| Variable Name | Type | Function |
| ------------- | ---- | -------- |
| `index[4]`| `TagTableIndex` | temporarily stores Tagged Table predictor entry indexes from which prediction was considered and made available in Updation Packet, `upd_pkt`|
| `tagTableEntry` | Array of `TagEntry` type with 4 elements | temporarily stores the Tag entries from Updation Packet, `upd_pkt` |
| `table_tags` | Array of `Tag` type with 4 elements | temporarily stores the computed tags from Updation Packet, `upd_pkt`|
| `tagtableNo` | `TableNo` type | stores the number of Tagged table predictors (`upd_pkt.tableNo - 1`) |
| `bimodal_index` | `BimodalIndex` | temporarily stores the bimodal index of the entry in Bimodal Table predictor which gave the prediction |
| `bimodalEntry` | `BimodalEntry` | temporarily stores the bimodal entry corresponding to the `bimodal_index` |
| `outcome` | `ActualOutcome` | temporarily stores the actual outcome of particular branch for which the updation has to be made |

#### Storing values from Updation Packet

The below code shows the storing of values from updation packet to temporary variables in order for further computations.

```
BimodalIndex bimodal_index = upd_pkt.bimodal_index;
BimodalEntry bimodalEntry = bimodal.sub(bimodal_index);
for(Integer i=0; i < `NUMTAGTABLES ; i=i+1) begin
	index[i] = upd_pkt.tagTable_index[i];
	tagTableEntry[i] = tagTables[i].sub(index[i]);
    table_tags[i] = upd_pkt.tableTag[i];
end
```

The indexes of each table entries which gave prediction are stored in temporary index variables. Similarly for tags of Tagged table predictors. As shown in code above.

Outcome of branch is stored as follows:

```
ActualOutcome outcome = upd_pkt.actualOutcome;
```

#### Updation of Tagged Table Predictors as per algorithm

Usefulness Counter of entries which gave prediction are updated as ahown below:

    if(upd_pkt.pred != upd_pkt.altpred) begin
    	if (upd_pkt.mispred == 1'b0 && upd_pkt.tableNo != 3'b000)
    		tagTableEntry[tagtableNo].uCtr = upd_pkt.uCtr[tagtableNo] + 2'b1;
        else
            tagTableEntry[tagtableNo].uCtr = upd_pkt.uCtr[tagtableNo] - 2'b1;
    end
If alternate prediction is different from final prediction, and the final prediction is correct, increment `uCtr`, otherwise decrement `uCtr`. Also a check for **not** a bimodal table is also included.

Provider component's prediction counter is incremented if actual outcome is TAKEN and decemented if actual outcome is NOT TAKEN. As shown below:

```
if(upd_pkt.actualOutcome == 1'b1) begin
	if(upd_pkt.tableNo == 3'b000)
		bimodalEntry.ctr = (bimodalEntry.ctr < 2'b11) ? (bimodalEntry.ctr + 2'b1) : 2'b11 ;
    else
        tagTableEntry[tagtableNo].ctr = (upd_pkt.ctr[tagtableNo+1]< 3'b111 )?(upd_pkt.ctr[tagtableNo+1] + 3'b1): 3'b111;
end
else begin
    if(upd_pkt.tableNo == 3'b000)
    	bimodalEntry.ctr = (bimodalEntry.ctr > 2'b00) ? (bimodalEntry.ctr - 2'b1) : 2'b00;
    else
		tagTableEntry[tagtableNo].ctr = (upd_pkt.ctr[tagtableNo+1] > 3'b000)?(upd_pkt.ctr[tagtableNo+1] - 3'b1): 3'b000;
end
```

**Allocation of new entry** :

This part of the code does the allocation of new entry using `allocate_entry()` function if there is a misprediction. Checks for table number in updation packet. See function section for the full algorithm.

    if (upd_pkt.mispred == 1'b1) begin
    	case (upd_pkt.tableNo)
            3'b000 :    tagTableEntry = allocate_entry(tagTableEntry, 0, table_tags, upd_pkt.actualOutcome);
            3'b001 :    tagTableEntry = allocate_entry(tagTableEntry, 1, table_tags, upd_pkt.actualOutcome);
            3'b010 :    tagTableEntry = allocate_entry(tagTableEntry, 2, table_tags, upd_pkt.actualOutcome);
            3'b011 :    tagTableEntry = allocate_entry(tagTableEntry, 3, table_tags, upd_pkt.actualOutcome);
        endcase
    end   
#### Assigning Changed variables to corresponding entries in Tagged Tables

The below code shows the assigning:

```
bimodal.upd(bimodal_index,bimodalEntry);
for(Integer i = 0 ; i < `NUMTAGTABLES ; i = i+1)
	tagTables[i].upd(index[i], tagTableEntry[i]);
```

### 3. output_packet()

This is a value method which outputs the prediction packet from the TAGE hardware.

```
method PredictionPacket output_packet();
	return pred_pkt;
endmethod
```

## Functions

| Function Name | Return value | Function Parameters | Description |
| ------------- | ------------ | ------------------- | ----------- |
| `update_GHR()` | GHR | GHR, prediction or actualoutcome| Updates the GHR based on prediction in the case of speculation and outcome in the case of reconstruction|
| `update_PHR()` | PHR | PHR, Program Counter | Updates the PHR based on program counter bit from PC |
| `allocate_entry` | Tag Entries | Tagged Table entries, Tags, actualoutcome |Allocation of new entry in Tagged Table predictors if there is misprediction|

### 1. update_GHR()

Update GHR speculatively with prediction or update GHR with actual outcome in the case of reconstruction. Append 1 if prediction or outcome is True. Else Append 0 if prediction or outcome is False.

```
t_ghr = (t_ghr << 1);
if(pred_or_outcome == 1'b1)
    t_ghr = t_ghr + 1;
```

###  2. update_PHR()

Update same as above according to PC bit.

### 3. allocate_entry()

Allocate new entry, if there is any u = 0 (not useful entry) for tables with longer history.

Three cases arise:  (all u>0 , one u = 0, more than one u = 0.)

1. For all u > 0, decrement all the u counters, No need to allocate new entry.
2. For one u = 0, allocate new entry to that index.
3. For more than one u = 0, allocate new entry to that which has longer history.

For the newly allocated entry, prediction counter is set to Weakly TAKEN or Weakly NOT TAKEN.
For the newly allocated entry, usefuleness counter is set to 0.
For the newly allocated entry, tag is the computed tag stored in the updation packet for that entry.

The code is shown below:

```
Bool allocate = False;
for (Integer i = 3; i >= tno; i = i - 1) begin    
    if(entries[i].uCtr == 2'b0 && allocate == False) begin
        entries[i].uCtr = 2'b0;
        entries[i].tag = tags[i];
        entries[i].ctr = (outcome == 1'b1) ? 3'b100 : 3'b011 ;
        allocate = True;
   	end
end
if (allocate == False) begin
	for (Integer i = tno; i <= 3; i = i + 1) 
     	entries[i].uCtr = 2'b0;
end
```