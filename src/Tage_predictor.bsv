package Tage_predictor;

    import Utils :: *;
    import Type_TAGE :: *;
    import RegFile :: *;
    import Vector :: *;

    `include "parameter.bsv"

    interface Tage_predictor_IFC;
        method Action computePrediction(ProgramCounter pc); //Indexing Table,Tag Computation, Comparison of Tag, Obtaining Prediction
        method Action updateTablePred(UpdationPacket upd_pkt);  //Updation of Usefulness Counter and Prediction Counter, Allocation of new entries in case of misprediction
        method PredictionPacket output_packet();    // Method to Output the prediction packet.
    endinterface

    //function to update GHR, based on speculation or during updation
    function GlobalHistory update_GHR(GlobalHistory t_ghr, Bit#(1) pred_or_outcome);
        t_ghr = (t_ghr << 1);       //to append 0 to LSB
        if(pred_or_outcome == 1'b1)
            t_ghr = t_ghr + 1;      //to append 1 to LSB
        return t_ghr;
    endfunction

    //function to update PHR, based on speculation or during updation
    function PathHistory update_PHR(PathHistory t_phr, ProgramCounter t_pc);
        t_phr = (t_phr << 1);    //to append 0 to LSB
        if(t_pc[2] == 1'b1)
            t_phr = t_phr + 1;   //to append 1 to LSB
        return t_phr;
    endfunction

    
    /* Allocate new entry, if there is any u = 0 (not useful entry) for tables with longer history 
            Three cases arise: all u>0 , one u = 0, more than one u = 0
            For all u > 0, decrement all the u counters, No need to allocate new entry
            For one u = 0, allocate new entry to that index
            For more than one u = 0, allocate new entry to that which has longer history
            For the newly allocated entry, prediction counter is set to Weakly TAKEN or Weakly NOT TAKEN.
            For the newly allocated entry, usefuleness counter is set to 0.
            For the newly allocated entry, tag is computed tag stored in the updation packet for that entry
    */
    function Vector#(`NUMTAGTABLES,TagEntry) allocate_entry(Vector#(`NUMTAGTABLES,TagEntry) entries, Integer tno, Vector#(`NUMTAGTABLES,Tag) tags, ActualOutcome outcome);
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
        return entries;
    endfunction



    (*synthesize*)
    module mkTage_predictor(Tage_predictor_IFC);

        let bimodal_max = fromInteger(`BIMODALSIZE-1);   //maximum sixe for Regfile of Bimodal Predictor Table
        let table_max = fromInteger(`TABLESIZE-1);       //maximum size for RegFile of Predictor tables

        Reg#(GlobalHistory) ghr <- mkReg(0);            //internal register to store GHR
        Reg#(PathHistory) phr <- mkReg(0);              //internal register to store PHR

        //RegFiles of Table Predictors in TAGE, one bimodal table predictor and four Tagged table predictors
        RegFile#(BimodalIndex, BimodalEntry) bimodal <- mkRegFile(0, bimodal_max);   //bimodal table
        RegFile#(TagTableIndex, TagEntry) table_0 <- mkRegFile(0, table_max);        //tagged table 0
        RegFile#(TagTableIndex, TagEntry) table_1 <- mkRegFile(0, table_max);        //tagged table 1
        RegFile#(TagTableIndex, TagEntry) table_2 <- mkRegFile(0, table_max);        //tagged table 2
        RegFile#(TagTableIndex, TagEntry) table_3 <- mkRegFile(0, table_max);        //tagged table 3
        
        RegFile#(TagTableIndex, TagEntry) tagTables[4] = {table_0, table_1, table_2, table_3}; //array of Tagged table predictors  
        
        Reg#(PredictionPacket) pred_pkt <- mkReg(unpack(0));  //output register to store prediction packet
        
        //Wires to take in values between methods and rules.
        Wire#(GlobalHistory) w_ghr <- mkWire();        //Wire for global history register
        Wire#(PathHistory) w_phr <- mkWire();          //Wire for path history register
        Wire#(ProgramCounter) w_pc <- mkWire();        //Wire for program counter
        Wire#(Prediction)  w_pred <- mkWire();         //wire for prediction
        Wire#(UpdationPacket) w_upd_pkt <- mkWire();   //wire for updation packet

        Wire#(Bool) w_pred_over <- mkWire();           //Wire to indicate prediction is over
        Wire#(Bool) w_update_over <- mkWire();         //Wire to indicate updation is over

        //rule to update the GHR and PHR when actualoutcome is obtained.
        rule rl_reconstruct_GHR_PHR(w_update_over == True);
            PathHistory t_phr = phr;
            GlobalHistory t_ghr = ghr;
            let t_upd_pkt = w_upd_pkt;
            // Misprediction if occured, reconstruct GHR and PHR 
            if (t_upd_pkt.mispred == 1'b1) begin
                t_upd_pkt.ghr = (t_upd_pkt.ghr >> 1);
                t_ghr = update_GHR(t_upd_pkt.ghr, t_upd_pkt.actualOutcome);
                t_phr = t_upd_pkt.phr;
            end

            w_pred_over <= True;
            w_ghr <= t_ghr;
            w_phr <= t_phr;

             `ifdef DEBUG
                $display("Value Assigned to Internal GHR(Updated) : %b", t_ghr);
                $display("Value Assigned to Internal PHR(Updated) : %b", t_phr);
            `endif

            `ifdef DEBUG
            $display("Entered rl_update");
            `endif
        endrule
        
        //rule to speculatively update GHR and PHR, once prediction is over.
        rule rl_spec_update_GHR_PHR (w_pred_over == True);
            w_ghr <= update_GHR(ghr, w_pred);
            w_phr <= update_PHR(phr, w_pc);

            let v_ghr = update_GHR(ghr, w_pred);
            let v_phr = update_PHR(phr, w_pc);

            `ifdef DEBUG
                $display("Value Assigned to Internal GHR(Speculative) : %b", v_ghr);
                $display("Value Assigned to Internal PHR(Speculative) : %b", v_phr);
            `endif

            `ifdef DEBUG
                $display("Entered rl_spec_update");
            `endif
        endrule

        //rule to write to internal GHR and PHR registers
        rule rl_GHR_PHR_write;
            ghr <= w_ghr;
            phr <= w_phr;
            
             `ifdef DISPLAY
                $display("Internal GHR(reflected only at next cycle): %b", w_ghr);
                $display("Internal PHR(reflected only at next cycle): %b", w_phr);
            `endif
 
            `ifdef DEBUG
                $display("Entered rl_GHR_PHR_write  ghr = %b, phr = %b", w_ghr, w_phr);    
            `endif
        endrule
       

        
        method Action computePrediction(ProgramCounter pc);

            //tags
            Tag computedTag[4];
            
            //indexes
            BimodalIndex bimodal_index;
            TagTableIndex tagTable_index[4];

            //variable to store temporary prediction packet
            PredictionPacket t_pred_pkt = unpack(0);

            //updating PHR in temporary prediction packet
            t_pred_pkt.phr = update_PHR(phr, pc);

            `ifdef DEBUG
                $display("\nGHR before prediction = %h",ghr);
                $display("\n\nPrediction Packet of last Prediction\n",fshow(pred_pkt), cur_cycle);
                $display("Calculating Index..... ");
            `endif

            //Indexing and Tagging
            //calling index computation function for each table and calling tag computation function for each table
            bimodal_index = truncate(computeIndex(pc,ghr,t_pred_pkt.phr,3'b000));
            t_pred_pkt.bimodal_index = bimodal_index;
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

            //Check for Tag Match
            //comparison of tag with the longest history table, getting prediction from it and alternate prediction from second longest tag matching table 
            t_pred_pkt.tableNo = 3'b000;
            t_pred_pkt.altpred = bimodal.sub(bimodal_index).ctr[1];
            t_pred_pkt.pred = bimodal.sub(bimodal_index).ctr[1];
            t_pred_pkt.ctr[0] = zeroExtend(bimodal.sub(bimodal_index).ctr);
            Bool matched = False;
            Bool altMatched = False;
            for (Integer i = 3; i >= 0; i=i-1) begin
                if(tagTables[i].sub(tagTable_index[i]).tag == computedTag[i] && !matched) begin
                    t_pred_pkt.ctr[i+1] = tagTables[i].sub(tagTable_index[i]).ctr;
                    t_pred_pkt.pred = tagTables[i].sub(tagTable_index[i]).ctr[2];
                    t_pred_pkt.tableNo = fromInteger(i+1); 
                    t_pred_pkt.uCtr[i] = tagTables[i].sub(tagTable_index[i]).uCtr;        
                    matched = True;
                end
                else if(tagTables[i].sub(tagTable_index[i]).tag == computedTag[i] && matched && !altMatched) begin
                    t_pred_pkt.altpred = tagTables[i].sub(tagTable_index[i]).ctr[2];
                    altMatched = True;
                end
            end

            //setting Wires for corresponding internal GHR and internal PHR updation in the rule
            w_pred <= t_pred_pkt.pred;              
            w_pc<=pc;

            //speculative update of GHR storing in temporary prediction packet
            t_pred_pkt.ghr = update_GHR(ghr, t_pred_pkt.pred);
            
            //assigning temporary prediction packet to prediction packet vector register
            pred_pkt <= t_pred_pkt;                     
            `ifdef  DEBUG
                $display("Current PC = %b", pc);
                $display("\nphr = %b",t_pred_pkt.phr);
                $display("\nPrediction Packet of current Prediction \n", fshow(t_pred_pkt), cur_cycle);
                $display("Prediction over....");
            `endif
            //to enable rl_spec_update_GHR_PHR
            w_pred_over <= True;           

        endmethod


        method Action updateTablePred(UpdationPacket upd_pkt);  
            
            /* Wires which indicate the onset of Updation of Tagged Table Predictors, passes the values
            rl_reconstruct_GHR_PHR rule */
            w_upd_pkt <= upd_pkt;                         //passes updation_packet       
            w_update_over <= True;                        //enables the rl_reconstruct_GHR_PHR rule


            //store the indexes of each entry of predictor tables from the updation packet
            //Store the corresponding indexed entry whose index is obtained from the updation packet
            TagTableIndex index[4];
            Vector#(`NUMTAGTABLES ,TagEntry) tagTableEntry;
            Vector#(`NUMTAGTABLES ,Tag) table_tags;

            TableNo tagtableNo = upd_pkt.tableNo-1;

            BimodalIndex bimodal_index = upd_pkt.bimodal_index;
            BimodalEntry bimodalEntry = bimodal.sub(bimodal_index);
            for(Integer i=0; i < `NUMTAGTABLES ; i=i+1) begin
                index[i] = upd_pkt.tagTable_index[i];
                tagTableEntry[i] = tagTables[i].sub(index[i]);
                table_tags[i] = upd_pkt.tableTag[i];
            end

            //store the actual outcome from the updation packet
            ActualOutcome outcome = upd_pkt.actualOutcome;

            `ifdef DEBUG
                $display("\n\nCurrent Updation Packet\n",fshow(upd_pkt));
                $display("Updation Packet Table Number = %b",upd_pkt.tableNo);
                $display("GHR = %h", upd_pkt.ghr );
            `endif

            //Updation of usefulness counter
            /* Usefulness counter is updated if the final prediction is different from alternate prediction, u is incremented if the prediction is correct
            u is decremented otherwise */
            if(upd_pkt.pred != upd_pkt.altpred) begin
                if (upd_pkt.mispred == 1'b0 && upd_pkt.tableNo != 3'b000)
                    tagTableEntry[tagtableNo].uCtr = upd_pkt.uCtr[tagtableNo] + 2'b1;
                else
                    tagTableEntry[tagtableNo].uCtr = upd_pkt.uCtr[tagtableNo] - 2'b1;
            end

            // updation of provider component's prediction counter
            /* Provider component's prediction counter is incremented if actual outcome is TAKEN and decremented if actual outcome is NOT TAKEN */
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

            //Allocation of new entries if there is a misprediction
            /* Allocate new entry, if there is any u = 0 (not useful entry) for tables with longer history 
            Three cases arise: all u>0 , one u = 0, more than one u = 0
            For all u > 0, decrement all the u counters, No need to allocate new entry
            For one u = 0, allocate new entry to that index
            For more than one u = 0, allocate new entry to that which has longer history
            For the newly allocated entry, prediction counter is set to Weakly TAKEN or Weakly NOT TAKEN.
            For the newly allocated entry, usefuleness counter is set to 0.
            For the newly allocated entry, tag is computed tag stored in the updation packet for that entry
            */
            if (upd_pkt.mispred == 1'b1) begin
                case (upd_pkt.tableNo)
                    3'b000 :    tagTableEntry = allocate_entry(tagTableEntry, 0, table_tags, upd_pkt.actualOutcome);
                    3'b001 :    tagTableEntry = allocate_entry(tagTableEntry, 1, table_tags, upd_pkt.actualOutcome);
                    3'b010 :    tagTableEntry = allocate_entry(tagTableEntry, 2, table_tags, upd_pkt.actualOutcome);
                    3'b011 :    tagTableEntry = allocate_entry(tagTableEntry, 3, table_tags, upd_pkt.actualOutcome);
                endcase
            end                    
            
            //Assigning back the corresponding entries to the prediction tables.
            bimodal.upd(bimodal_index,bimodalEntry);
            for(Integer i = 0 ; i < `NUMTAGTABLES ; i = i+1)
                tagTables[i].upd(index[i], tagTableEntry[i]);

            `ifdef DISPLAY
                $display("Updation over\n");
            `endif

        endmethod

        //method that outputs the prediction packet
        method PredictionPacket output_packet(); 
            return pred_pkt;
        endmethod

    endmodule

endpackage
