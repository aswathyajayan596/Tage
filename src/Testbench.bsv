package Testbench;

  import Tage_predictor   :: *;    //Tage predictor module as per algorithm
  import Type_TAGE        :: *;    //Types declarations
  import Utils            :: *;    //Display of current_cycle
  import RegFile          :: *;    //For trace files
  import Vector           :: *;    //for performance counters

  `include "parameter_tage.bsv"         // for traceSize that is parameterized.

  //for generating updation packet after obtaining branch instruction outcome
  function UpdationPacket get_updation_pkt(PredictionPacket t_pred_pkt1, Bit#(1) t_actual_outcome);

    UpdationPacket t_upd_pkt = unpack(0);
    let mispred = ( t_actual_outcome == t_pred_pkt1.pred ) ? 1'b0 : 1'b1;  //misprediction check
  t_upd_pkt = UpdationPacket {    
                                  mispred : mispred, 
                                  actualOutcome:  t_actual_outcome,
                                  bimodal_index:   t_pred_pkt1.bimodal_index,
                                  tagTable_index:  t_pred_pkt1.tagTable_index,
                                  tableTag:       t_pred_pkt1.tableTag,
                                  uCtr:           t_pred_pkt1.uCtr,
                                  bCtr:           t_pred_pkt1.bCtr, 
                                  ctr:            t_pred_pkt1.ctr,
                                  ghr:            t_pred_pkt1.ghr,
                                  phr:            t_pred_pkt1.phr,
                                  tableNo:        t_pred_pkt1.tableNo,
                                  altpred:        t_pred_pkt1.altpred,
                                  pred:           t_pred_pkt1.pred,
                                  index_csr: t_pred_pkt1.index_csr,
                                  tag1_csr1:  t_pred_pkt1.tag1_csr1,
                                  tag1_csr2:  t_pred_pkt1.tag1_csr2,
                                  tag2_csr1: t_pred_pkt1.tag2_csr1,
                                  tag2_csr2: t_pred_pkt1.tag2_csr2
                                };
    return t_upd_pkt;

  endfunction


  module mkTestbench(Empty);

    //trace files containing branch addresses and outcomes
    RegFile#(Bit#(32), Bit#(64)) branches                      <-  mkRegFileFullLoad("trace_files/traces_br.hex");
    RegFile#(Bit#(32), Bit#(1)) actualOutcome                  <-  mkRegFileFullLoad("trace_files/traces_outcome.hex");

    //Based on TAGE predictor design
    Tage_predictor_IFC predictor                               <-  mkTage_predictor;
    Reg#(PredictionPacket) pred_pkt                            <-  mkReg(unpack(0));
    Reg#(UpdationPacket) upd_pkt                               <-  mkReg(unpack(0));

    //program flow control register
    Reg#(Bit#(32)) ctr                                         <-  mkReg(0);
    Reg#(Bool)     rl_dsply_ctrl                             <-  mkReg(True);

    //Performance monitoring counters
    Reg#(Int#(32)) correct                                     <-  mkReg(0);
    Reg#(Int#(32)) incorrect                                   <-  mkReg(0);
    Vector#(5, Reg#(TableCounters)) table_ctr                  <-  replicateM(mkReg(unpack(0)));


    //performance monitoring counter updation
    function Action table_counters(TableNo tableno, Misprediction mispred);
        action
            let tno = pack(tableno);
            if (mispred == 1'b0)  //increment correct prediction counter of corresponding table if there is no misprediction
                table_ctr[tno].predictionCtr <= table_ctr[tno].predictionCtr + 1;
            else                 //increment incorrect prediction counter of corresponding table if there is a misprediction
                table_ctr[tno].mispredictionCtr <= table_ctr[tno].mispredictionCtr + 1;
        endaction
    endfunction


    /*
    * Rule:  rl_display_and_table_reset
    * --------------------
    * calls the TAGE internal display method initiates  
    * resetting of entries in tables.
    * 
    * After resetting the control (ctr) is updated for rule initial 
    * to fire and start prediction.
    * rl_dsply_ctrl is set to false after internal display is enabled
    * and when reset is over
    */
    //to enable internal display from the very beginning.
    rule rl_display_and_table_reset(ctr == 0 && rl_dsply_ctrl); 
      $display("In rule display_and_table_reset...", cur_cycle);
      predictor.displayInternal(True);
      ctr <= ctr+1;
      rl_dsply_ctrl <= False;
    endrule    

    /*
    * Rule: rl_init_or_mispred
    * Fires: during initial as well as after misprediction
    * -----------------------
    * During start of prediction and after misprediction,
    * only computePrediction method needs to be fired.
    */
    rule rl_init_or_mispred( (ctr == 1 || upd_pkt.mispred == 1'b1)  && !rl_dsply_ctrl);
      $display("\n\n----In rule init_or_mispred...", cur_cycle);
      /* at the start, index of first pc is at 0. In case of misprediction, 
         mispredicted pc is updated with actual outcome and prediction start
         over from updated pc value(current pc). */
      let pc = branches.sub(ctr-1);

      // $display("PC = %h", pc);
      // calls method for prediction of current PC.
      predictor.computePrediction(pc);
      // reset the updation packet to clear the last state. 
      upd_pkt <= unpack(0);  
      ctr <= ctr + 1;
    endrule

    /* 
    * Rule: rl_comp_pred_upd
    * Fires when there is no misprediction and between initial and last cycles
    * ------------------------
    * Updation of tables from the previous PC is done first, followed by 
    * compute prediction of current PC in case of no misprediction.
    */
    rule rl_comp_pred_upd (ctr < `traceSize+1 && ctr > 1 && upd_pkt.mispred == 1'b0 );

      $display("\n\nIn rule compute prediction and updation...", cur_cycle);

      PredictionPacket t_pred_pkt = unpack(0);
      UpdationPacket t_u_pkt = unpack(0);
      let pc = branches.sub(ctr-1);
      $display("PC = %h", pc);
      t_pred_pkt = predictor.output_packet();

      t_u_pkt = get_updation_pkt(t_pred_pkt, actualOutcome.sub((ctr-2)));

      upd_pkt <= get_updation_pkt(t_pred_pkt, actualOutcome.sub((ctr-2)));
      predictor.updateTablePred(t_u_pkt);

      //updating the performance monitoring counters based on 
      //the misprediction result obtained in the current cycle
      table_counters(t_u_pkt.tableNo, t_u_pkt.mispred);
      if(t_u_pkt.mispred == 1'b1) begin
        $display("Misprediction occured");
        ctr <= ctr;  /* update ctr to the current ctr so that the prediction
        can be done from the current cycle which mispredicted the previous branch*/
        incorrect <= incorrect + 1; //increment performance counter based on this
      end
      else begin
        $display("No misprediction.. Performing prediction of current PC");
        predictor.computePrediction(pc); //compute prediction for the current PC 
                                          // if there is no misprediction
        ctr <= ctr + 1; /* update ctr to the next ctr so that the prediction
        can be done from the next cycle since there is no misprediction */
        correct <= correct + 1;  //increment performance counter based on this
      end
    endrule

    

    

    rule end_simulation(ctr == `traceSize+1);

        $display("In rule end_simulation.. ", cur_cycle);

        $display("Result:%d,%d", correct, incorrect);           

        // $display("\nBimodal Table \n", fshow(table_ctr[0]));
        // $display("\nTable 1\n", fshow(table_ctr[1]));
        // $display("\nTable 2 \n", fshow(table_ctr[2]));
        // $display("\nTable 3 \n", fshow(table_ctr[3]));
        // $display("\nTable 4 \n", fshow(table_ctr[4]));

    $finish(0);

    endrule

  endmodule
endpackage
