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
        Reg#(Bool)     display_enabled                             <-  mkReg(True);

        //Performance monitoring counters
        Reg#(Int#(32)) correct                                     <-  mkReg(0);
        Reg#(Int#(32)) incorrect                                   <-  mkReg(0);
        Vector#(5, Reg#(TableCounters)) table_ctr                  <-  replicateM(mkReg(unpack(0)));

        let fh <- mkReg(InvalidFile) ;

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
        

        //execute this at the start as well as there is misprediction (inorder to start over)
        rule rl_initial( ctr == 1   || upd_pkt.mispred == 1'b1  && !display_enabled);
            `ifdef TAGE_DISPLAY
                $fdisplay(fh, "\n=====================================================================================================================");
                $fdisplay(fh, "\nCycle %d   Ctr %d",cur_cycle, ctr);
            `endif

            `ifdef TAGE_DISPLAY
                if (upd_pkt.mispred == 1'b1)
                    $fdisplay(fh, "\nMisprediction happened in last iteration. Starting from current PC");
            `endif

            let pc = branches.sub(ctr-1);

            `ifdef TAGE_DISPLAY
                $fdisplay(fh, "\nCurrent Branch Address, PC =  %h", pc, cur_cycle); 
            `endif

            predictor.computePrediction(pc);

            `ifdef TAGE_DISPLAY
                $fdisplay(fh, "Prediction started, Prediction for current branch address will be obtained in the next cycle");
            `endif

            ctr <= ctr + 1;
            upd_pkt <= unpack(0);

        endrule

        rule rl_comp_pred_upd (ctr < `traceSize+1 && ctr > 1 && upd_pkt.mispred == 1'b0);
                        
            `ifdef TAGE_DISPLAY
                $fdisplay(fh, "\n=====================================================================================================================");
                $fdisplay(fh, "\nCycle %d   Ctr %d",cur_cycle, ctr);
            `endif

            PredictionPacket t_pred_pkt = unpack(0);
            UpdationPacket t_u_pkt = unpack(0);
            let pc = branches.sub(ctr-1);
            t_pred_pkt = predictor.output_packet();

            `ifdef TAGE_DISPLAY
                $fdisplay(fh, "\n--------------------------------------------  Prediction Packet -------------------------------------- \n",fshow(t_pred_pkt), cur_cycle);
                $fdisplay(fh, "--------------------------------------------------------------------------------------------------------");
            `endif

            `ifdef TAGE_DISPLAY
                $fdisplay(fh, "\nProgram Counter of Last Branch =  %h", branches.sub(ctr-2));
                $fdisplay(fh, "Prediction of Last Branch = %b", t_pred_pkt.pred);
            `endif

            // $fdisplay(fh, "Prediction of Last Branch = %b", t_pred_pkt.pred);
            // $fdisplay(fh, "Alternate Prediction of Last Branch = %b", t_pred_pkt.altpred);
            // $fdisplay(fh, "Prediction from Table: %d", t_pred_pkt.tableNo);

            t_u_pkt = get_updation_pkt(t_pred_pkt, actualOutcome.sub((ctr-2)));


            `ifdef TAGE_DISPLAY  
                $fdisplay(fh, "Outcome of Last branch assigned to Updation_Packet = %b", t_u_pkt.actualOutcome, cur_cycle);
            `endif

            upd_pkt <= get_updation_pkt(t_pred_pkt, actualOutcome.sub((ctr-2)));
            predictor.updateTablePred(t_u_pkt);

             `ifdef TAGE_DISPLAY 
                $fdisplay(fh, "\n\n\n------------------------------------------  Updation Packet --------------------------------------------- \n",fshow(t_u_pkt), cur_cycle);
                $fdisplay(fh, "-------------------------------------------------------------------------------------------------------------");
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
                
                `ifdef TAGE_DISPLAY
                    $fdisplay(fh, "\nCurrent Branch Address, PC =  %h", pc, cur_cycle);  
                    $fdisplay(fh, "Prediction started, Prediction for current branch address will be obtained in the next cycle");
                `endif
                
                ctr <= ctr + 1; /* update ctr to the next ctr so that the prediction
                can be done from the next cycle since there is no misprediction */

                correct <= correct + 1;  //increment performance counter based on this
            end
        endrule

        rule rl_display(ctr == 0 && display_enabled);      //fdisplay fh, rule for displaying the current cycle
            predictor.displayInternal(False);
            ctr <= ctr+1;
            display_enabled <= False;

            // $fdisplay(fh, "\n=====================================================================================================================");
            // $fdisplay(fh, "\nCycle %d   Ctr %d",cur_cycle, ctr);

            // `ifdef TAGE_DISPLAY
            //     $fdisplay(fh, "\n=====================================================================================================================");
            //     $fdisplay(fh, "\nCycle %d   Ctr %d",cur_cycle, ctr);
            // `endif
        endrule
    
        

        rule end_simulation(ctr == `traceSize+1);
            $display("Result:%d,%d", correct, incorrect);
            $fdisplay(fh, "Result:%d,%d", correct, incorrect);
            `ifdef
                $fdisplay(fh,"Result:%d,%d", correct, incorrect);      
            // $fdisplay(fh, "Result: Correct = %d, Incorrect = %d", correct, incorrect);
            `endif
           

        `ifdef TAGE_DISPLAY
            // $fdisplay(fh, "Incorrect = %d      Correct = %d",incorrect,correct);
            $fdisplay(fh, "\nBimodal Table \n", fshow(table_ctr[0]));
            $fdisplay(fh, "\nTable 1\n", fshow(table_ctr[1]));
            $fdisplay(fh, "\nTable 2 \n", fshow(table_ctr[2]));
            $fdisplay(fh, "\nTable 3 \n", fshow(table_ctr[3]));
            $fdisplay(fh, "\nTable 4 \n", fshow(table_ctr[4]));
        `endif

        $finish(0);

        endrule

    endmodule
endpackage
