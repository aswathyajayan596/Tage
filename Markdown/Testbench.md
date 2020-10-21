## `Testbench.bsv`

The testbench is for passing in the inputs and getting output to ensure proper working of the `TAGE_predictor` design.

The different structures/variables used along with their functionality is given in the table below:

| Structure/Variable Name | Functionality | Remarks |
| ----------------------- | ------------- | ------- |
| `branches`| stores the current branch address of which prediction needs to be done | loads value from trace file |
| `actualOutcome` | stores the actual outcome of the branch address | loads value from the trace file |
| `predictor` | instance of TAGE predictor | inputs and outputs are given through its interface |
| `pred_pkt` | stores the output of the TAGE predictor as Prediction Packet | obtained at the next cycle after the inputs for prediction are given |
| `upd_pkt` | stores the Updation Packet to be given as input to the Predictor | It is given as soon as the Prediction Packet is obtained |
| `ctr` | Program flow control register | controls the program flow based on the available number of traces (line number in trace file) |
| `correct` | stores the number of correct predictions on each iteration | Performance monitoring counter |
| `incorrect` | stores the number of wrong prediction on each iteration | Performance monitoring counter |
| `table_ctr` | stores the correct and incorrect predictions from each table predictors | Performance monitoring counter for each table predictors |

### Functions

The different functions used are as follows:

#### `get_updation_pkt()`

The function is used to obtain the updation packet for giving as input to the predictor for updation. For testing, the prediction packet, obtained after the prediction, is modified by adding the misprediction bit and actual outcome of the predicted branch to the updation packet. 

The mispred bit is created by checking if actual_outcome and prediction are equal, as shown:

```
let mispred = ( t_actual_outcome == t_pred_pkt1.pred ) ? 1'b0 : 1'b1;
```

The function returns the Updation Packet.

#### `table_counters()`

The function is for the performance monitoring counters for each table predictors. Increments the corresponding counters of each tabe predictor based on correct prediction or misprediction. 

| Variable Name | Value | Description       |
| ------------- | ----- | ----------------- |
| `mispred`     | 0     | no  misprediction |
| `mispred` | 1 | misprediction |

### Rules

#### `rl_display`

For displaying the current cycle for each iteration. Fires all the time.

#### `rl_initial`

This rule is fired either in the beginning or there is a misprediction.

At the beginning of the program, the address of branch instruction is initialised to `pc`. And prediction is computed. 

```
let pc = branches.sub(ctr);
predictor.computePrediction(pc);
```

The program control register is incremented to point to the next cycle.

```
ctr <= ctr + 1;
upd_pkt <= unpack(0); 
```

Also clears the updation packet for the next iteration, if the last iteration lead to misprediction.

#### `rl_comp_pred_upd`

Rule containing the updation of the previous branch and the prediction of current branch (if there had been no misprediction).

The prediction packet for the last branch is obtained:

```
t_pred_pkt = predictor.output_packet();
```

Obtaining the modified updation packet of previous branch (actual outcome is for `ctr-1`) for giving as input to the predictor:

```
t_u_pkt = get_updation_pkt(t_pred_pkt, actualOutcome.sub((ctr-1)));
```

Providing the prediction packet for updation:

```
predictor.updateTablePred(t_u_pkt);
```

Updating the table_counters:

```
table_counters(t_u_pkt.tableNo, t_u_pkt.mispred);
```

If there has been a misprediction the `ctr` is updated to point to the current branch. Incorrect is incremented. If there is no misprediction, prediction is made for the current branch and `ctr` is made to point to the next branch. Correct is incremented.

```
if(t_u_pkt.mispred == 1'b1) begin
	ctr <= ctr;
	incorrect <= incorrect + 1;
end
else begin
	predictor.computePrediction(pc);
	ctr <= ctr + 1;
	correct <= correct + 1;
end
```

#### `rl_end_simulation`

Displays the results at the end of simulation.

