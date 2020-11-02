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

    function Action check_u_counters(Vector#(4,TagEntry) entries);
        action
            Integer found = 0;
            $display("Found value = %d", found);
            for (Integer i=0; i<4; i=i+1) begin
                if (entries[i].uCtr > 0) begin
                    found = found + 1;
                end
            end
            if(found == 4) begin
                $display("Found value = %d", found);
                $display("Found all u>0", fshow(entries));
                $display("\n");
            end
        endaction
    endfunction

    function GlobalHistory update_GHR(GlobalHistory t_ghr, Bit#(1) pred_or_outcome);
        t_ghr = (t_ghr << 1);
        t_ghr[0] = pred_or_outcome;
        return t_ghr;
    endfunction

    function PathHistory update_PHR(PathHistory t_phr, ProgramCounter t_pc);
        t_phr = (t_phr << 1);   
        t_phr[0] = t_pc[2];   
        return t_phr;
    endfunction

    function Vector#(4,TagEntry) allocate_entry(Vector#(4,TagEntry) entries, Integer tno, Vector#(4,Tag) tags, ActualOutcome outcome);
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
        Wire#(GlobalHistory) dw_ghr <- mkDWire(0);        //Wire for global history register
        Wire#(PathHistory) dw_phr <- mkDWire(0);          //Wire for path history register
        Wire#(ProgramCounter) dw_pc <- mkDWire(0);        //Wire for program counter
        Wire#(Prediction)  dw_pred <- mkDWire(0);         //wire for prediction
        Wire#(Misprediction) dw_mispred <- mkDWire(0); 
        Wire#(ActualOutcome) dw_outcome <- mkDWire(0);

        Wire#(Bool) dw_pred_over <- mkDWire(False);           //Wire to indicate prediction is over
        Wire#(Bool) dw_update_over <- mkDWire(False);         //Wire to indicate updation is over

        //rule to update the GHR and PHR when actualoutcome is obtained.
        rule rl_update_GHR_PHR;
            PathHistory t_phr = 0;
            GlobalHistory t_ghr = 0;
            // Misprediction if occured, reconstruct GHR and PHR 
            if (dw_mispred == 1'b1) begin
                t_ghr = dw_ghr;
                t_ghr = update_GHR(t_ghr, dw_outcome);
                t_phr = dw_phr;
            end
            else if(dw_pred_over) begin
                t_ghr = update_GHR(ghr, dw_pred);
                t_phr = update_PHR(phr, dw_pc);
            end
            ghr <= t_ghr;
            phr <= t_phr;

             `ifdef DEBUG
                $display("Value Assigned to Internal GHR(Updated) : %b", t_ghr);
                $display("Value Assigned to Internal PHR(Updated) : %b", t_phr);
            `endif

            `ifdef DEBUG
            $display("Entered rl_update");
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

            //calling index computation function for each table and calling tag computation function for each table
            bimodal_index = truncate(compFoldIndex(pc,ghr,t_pred_pkt.phr,3'b000));
            t_pred_pkt.bimodal_index = bimodal_index;
            for (Integer i = 0; i < 4; i=i+1) begin
                TableNo tNo = fromInteger(i+1);
                tagTable_index[i] = truncate(compFoldIndex(pc,ghr,t_pred_pkt.phr,tNo));
                t_pred_pkt.tagTable_index[i] = tagTable_index[i];
                if(i<2) begin
                    computedTag[i] = tagged Tag1 truncate(compFoldTag(pc,ghr,tNo));
                    t_pred_pkt.tableTag[i] = computedTag[i];
                end
                else begin
                    computedTag[i] = tagged Tag2 truncate(compFoldTag(pc,ghr,tNo));
                    t_pred_pkt.tableTag[i] = computedTag[i];
                end
            end


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

            
            dw_pred <= t_pred_pkt.pred;              //setting RWire for corresponding GHR updation in the rule
            dw_pc<=pc;

            //speculative update of GHR storing in temporary prediction packet
            t_pred_pkt.ghr = ghr;
            
            pred_pkt <= t_pred_pkt;                     //assigning temporary prediction packet to prediction packet vector register
            `ifdef  DEBUG
                $display("Current PC = %b", pc);
                $display("\nphr = %b",t_pred_pkt.phr);
                $display("\nPrediction Packet of current Prediction \n", fshow(t_pred_pkt), cur_cycle);
                $display("Prediction over....");
            `endif
           
           dw_pred_over <= True;           

        endmethod


        method Action updateTablePred(UpdationPacket upd_pkt);  
            
            dw_ghr <= upd_pkt.ghr;
            dw_phr <= upd_pkt.phr;
            dw_outcome <= upd_pkt.actualOutcome;
            dw_mispred <= upd_pkt.mispred;

            dw_update_over <= True;
            //store the indexes of each entry of predictor tables from the updation packet
            //Store the corresponding indexed entry whose index is obtained from the updation packet
            TagTableIndex ind[4];
            Vector#(4,TagEntry) tag_table_entries;
            Vector#(4,Tag) table_tags;

            TableNo tagtableNo = upd_pkt.tableNo-1;

            BimodalIndex bindex = upd_pkt.bimodal_index;
            BimodalEntry t_bimodal = bimodal.sub(bindex);
            for(Integer i=0; i < 4; i=i+1) begin
                ind[i] = upd_pkt.tagTable_index[i];
                tag_table_entries[i] = tagTables[i].sub(ind[i]);
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


            if (upd_pkt.pred != upd_pkt.altpred) begin
                if (upd_pkt.mispred == 1'b0 && upd_pkt.tableNo != 3'b000)
                    tag_table_entries[tagtableNo].uCtr = upd_pkt.uCtr[tagtableNo] + 2'b1;
                else
                    tag_table_entries[tagtableNo].uCtr = upd_pkt.uCtr[tagtableNo] - 2'b1;
            end

            // updation of provider component's prediction counter
            /* Provider component's prediction counter is incremented if actual outcome is TAKEN and decremented if actual outcome is NOT TAKEN */

            if(upd_pkt.actualOutcome == 1'b1) begin
                if(upd_pkt.tableNo == 3'b000)
                    t_bimodal.ctr = (t_bimodal.ctr < 2'b11) ? (t_bimodal.ctr + 2'b1) : 2'b11 ;
                else
                    tag_table_entries[tagtableNo].ctr = (upd_pkt.ctr[tagtableNo+1]< 3'b111 )?(upd_pkt.ctr[tagtableNo+1] + 3'b1): 3'b111;
            end
            else begin
                if(upd_pkt.tableNo == 3'b000)
                    t_bimodal.ctr = (t_bimodal.ctr > 2'b00) ? (t_bimodal.ctr - 2'b1) : 2'b00;
                else
                    tag_table_entries[tagtableNo].ctr = (upd_pkt.ctr[tagtableNo+1] > 3'b000)?(upd_pkt.ctr[tagtableNo+1] - 3'b1): 3'b000;
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
            
            check_u_counters(tag_table_entries);

            if (upd_pkt.mispred == 1'b1) begin
                case (upd_pkt.tableNo)
                    3'b000 :    tag_table_entries = allocate_entry(tag_table_entries, 0, table_tags, upd_pkt.actualOutcome);
                    3'b001 :    tag_table_entries = allocate_entry(tag_table_entries, 1, table_tags, upd_pkt.actualOutcome);
                    3'b010 :    tag_table_entries = allocate_entry(tag_table_entries, 2, table_tags, upd_pkt.actualOutcome);
                    3'b011 :    tag_table_entries = allocate_entry(tag_table_entries, 3, table_tags, upd_pkt.actualOutcome);
                endcase
            end                    
            
            //Assigning back the corresponding entries to the prediction tables.
            bimodal.upd(bindex,t_bimodal);
            for(Integer i = 0 ; i < 4; i = i+1)
                tagTables[i].upd(ind[i], t_table[i]);

            `ifdef DISPLAY
                $display("Updation over\n");
            `endif

        endmethod

        method PredictionPacket output_packet(); //method that outputs the prediction packet
            return pred_pkt;
        endmethod

    endmodule

endpackage
