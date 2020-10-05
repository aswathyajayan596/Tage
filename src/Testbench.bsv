package Testbench;

    import Tage_predictor   :: *;    //Tage predictor module as per algorithm
    import Type_TAGE        :: *;    //Types declarations
    import Utils            :: *;    //Display of current_cycle
    import RegFile          :: *;    //For trace files
    import Vector           :: *;    //for performance counters


    `include "parameter.bsv"         // for traceSize that is parameterized.

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
                                        ctr:            t_pred_pkt1.ctr,
                                        ghr:            t_pred_pkt1.ghr,
                                        phr:            t_pred_pkt1.phr,
                                        tableNo:        t_pred_pkt1.tableNo,
                                        altpred:        t_pred_pkt1.altpred,
                                        pred:           t_pred_pkt1.pred
                                   };
        return t_upd_pkt;

    endfunction


    module mkTestbench(Empty);

        //trace files containing branch addresses and outcomes
        RegFile#(Bit#(22), Bit#(64)) branches                      <-  mkRegFileFullLoad("trace_files/traces_br.hex");
        RegFile#(Bit#(22), Bit#(1)) actualOutcome                  <-  mkRegFileFullLoad("trace_files/traces_outcome.hex");

        //Based on TAGE predictor design
        Tage_predictor_IFC predictor                               <-  mkTage_predictor;
        Reg#(PredictionPacket) pred_pkt                            <-  mkReg(unpack(0));
        Reg#(UpdationPacket) upd_pkt                               <-  mkReg(unpack(0));

        //program flow control register
        Reg#(Bit#(22)) ctr                                         <-  mkReg(0);

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


       
        rule rl_display(ctr >= 0);      //display rule for displaying the current cycle
            `ifdef DISPLAY
                $display("\n=====================================================================================================================");
                $display("\nCycle %d   Ctr %d",cur_cycle, ctr);
            `endif
        endrule


        //execute this at the start as well as there is misprediction (inorder to start over)
        rule rl_initial(ctr == 0 || upd_pkt.mispred == 1'b1 );

            `ifdef DISPLAY
                if (upd_pkt.mispred == 1'b1)
                    $display("\nMisprediction happened in last iteration. Starting from current PC");
            `endif

            let pc = branches.sub(ctr);

            `ifdef DISPLAY
                $display("\nCurrent Branch Address, PC =  %h", pc, cur_cycle); 
            `endif

            predictor.computePrediction(pc);

            `ifdef DISPLAY
                $display("Prediction started, Prediction for current branch address will be obtained in the next cycle");
            `endif

            ctr <= ctr + 1;
            upd_pkt <= unpack(0);

        endrule

        rule rl_comp_pred_upd (ctr < `traceSize+1 && ctr > 0 && upd_pkt.mispred == 1'b0);

            PredictionPacket t_pred_pkt = unpack(0);
            UpdationPacket t_u_pkt = unpack(0);
            let pc = branches.sub(ctr);
            t_pred_pkt = predictor.output_packet();
            `ifdef DISPLAY
                $display("\n--------------------------------------------  Prediction Packet -------------------------------------- \n",fshow(t_pred_pkt), cur_cycle);
                $display("--------------------------------------------------------------------------------------------------------");
            `endif
            `ifdef DISPLAY
                $display("\nProgram Counter of Last Branch =  %h", branches.sub(ctr-1));
                $display("Prediction of Last Branch = %b", t_pred_pkt.pred);
            `endif

            t_u_pkt = get_updation_pkt(t_pred_pkt, actualOutcome.sub((ctr-1)));

            `ifdef DISPLAY  
                $display("Outcome of Last branch assigned to Updation_Packet = %b", t_u_pkt.actualOutcome, cur_cycle);
            `endif

            upd_pkt <= get_updation_pkt(t_pred_pkt, actualOutcome.sub((ctr-1)));
            predictor.updateTablePred(t_u_pkt);

             `ifdef DISPLAY 
                $display("\n\n\n------------------------------------------  Updation Packet --------------------------------------------- \n",fshow(t_u_pkt), cur_cycle);
                $display("-------------------------------------------------------------------------------------------------------------");
            `endif
            //updating the performance monitoring counters based on the misprediction result obtained in the current cycle
            table_counters(t_u_pkt.tableNo, t_u_pkt.mispred);
            if(t_u_pkt.mispred == 1'b1) begin
                ctr <= ctr;  /* update ctr to the current ctr so that the prediction
                can be done from the current cycle which mispredicted the previous branch */
                incorrect <= incorrect + 1; //increment performance counter based on this
                end
            else begin

                predictor.computePrediction(pc); //compute prediction for the current PC if there is no misprediction

                `ifdef DISPLAY
                    $display("\nCurrent Branch Address, PC =  %h", pc, cur_cycle);  
                    $display("Prediction started, Prediction for current branch address will be obtained in the next cycle");
                `endif

                ctr <= ctr + 1; /* update ctr to the next ctr so that the prediction
                can be done from the next cycle since there is no misprediction */

                correct <= correct + 1;  //increment performance counter based on this
            end

        endrule

        rule end_simulation(ctr == `traceSize+1);

            // $display("Result:%d,%d", correct, incorrect);
            $display("Result: Correct = %d, Incorrect = %d", correct, incorrect);

            // `ifdef DISPLAY
                // $display("Incorrect = %d      Correct = %d",incorrect,correct);
                $display("\nBimodal Table \n", fshow(table_ctr[0]));
                $display("\nTable 1\n", fshow(table_ctr[1]));
                $display("\nTable 2 \n", fshow(table_ctr[2]));
                $display("\nTable 3 \n", fshow(table_ctr[3]));
                $display("\nTable 4 \n", fshow(table_ctr[4]));
            // `endif

            $finish(0);

        endrule

    endmodule
endpackage
