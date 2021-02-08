package Tage_predictor;

  import Utils :: *;
  import Type_TAGE :: *;
  import RegFile :: *;
  import Vector :: *;

  `include "parameter_tage.bsv"

  interface Tage_predictor_IFC;
      method Action computePrediction(ProgramCounter pc); //Indexing Table,Tag Computation, Comparison of Tag, Obtaining Prediction
      method Action updateTablePred(UpdationPacket upd_pkt);  //Updation of Usefulness Counter and Prediction Counter, Allocation of new entries in case of misprediction
      method PredictionPacket output_packet();    // Method to Output the prediction packet.
      method Action displayInternal(Bool start_display);
  endinterface

 

  function GlobalHistory update_GHR(GlobalHistory t_ghr, Bit#(1) pred_or_outcome);
      t_ghr = (t_ghr << 1);
      t_ghr[0] = pred_or_outcome;
      return t_ghr;
  endfunction

  function PathHistory update_PHR(PathHistory t_phr, PC_bit t_pc);
      t_phr = (t_phr << 1);   
      t_phr[0] = t_pc;   
      return t_phr;
  endfunction

  function Vector#(`NUMTAGTABLES, TagEntry) allocate_entry(Vector#(`NUMTAGTABLES, TagEntry) entries, Integer tno, Vector#(`NUMTAGTABLES,Tag) tags, ActualOutcome outcome);
      Bool allocate = False;
      for (Integer i = 3; i >= 0; i = i - 1) begin
              if(i >= tno) begin
                  if(entries[i].uCtr == 2'b0 && allocate == False) begin
                  entries[i].uCtr = 2'b0;
                  entries[i].tag = tags[i];
                  entries[i].ctr = (outcome == 1'b1) ? 3'b100 : 3'b011 ;
                  allocate = True;
              end
          end
      end
      if (allocate == False) begin
          for (Integer i = 0; i < `NUMTAGTABLES; i = i + 1) begin
              if (i > tno)
                  entries[i].uCtr = entries[i].uCtr - 2'b1;
          end
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

    Vector#(TSub#(`NUMTAGTABLES,1), Reg#(CSR)) reg_index_csr  <-  replicateM(mkReg(unpack(0)));

    Vector#(2, Reg#(CSR))      reg_tag1_csr1   <-  replicateM(mkReg(unpack(0)));
    Vector#(2, Reg#(CSR))      reg_tag1_csr2   <-  replicateM(mkReg(unpack(0)));
    Vector#(2, Reg#(CSR))      reg_tag2_csr1   <-  replicateM(mkReg(unpack(0)));
    Vector#(2, Reg#(CSR))      reg_tag2_csr2   <-  replicateM(mkReg(unpack(0)));
    
    RegFile#(TagTableIndex, TagEntry) tagTables[`NUMTAGTABLES] = {table_0, table_1, table_2, table_3}; //array of Tagged table predictors  
    
    Reg#(PredictionPacket) pred_pkt <- mkReg(unpack(0));  //output register to store prediction packet
    
    //Wires to take in values between methods and rules.
    Wire#(GlobalHistory) dw_ghr <- mkDWire(0);        //Wire for global history register
    Wire#(PathHistory) dw_phr <- mkDWire(0);          //Wire for path history register
    Wire#(PC_bit) dw_pc_bit <- mkDWire(0);        //Wire for program counter
    Wire#(Prediction)  dw_pred <- mkDWire(0);         //wire for prediction
    Wire#(Misprediction) dw_mispred <- mkDWire(0); 
    Wire#(ActualOutcome) dw_outcome <- mkDWire(0);

    Wire#(Bool) dw_pred_over <- mkDWire(False);           //Wire to indicate prediction is over
    Wire#(Bool) dw_update_over <- mkDWire(False);         //Wire to indicate updation is over

    Reg#(Bool)     rg_resetting <- mkReg (True);
    Reg#(BimodalIndex)   rst_ctr_b <- mkReg(0);
    Reg#(TagTableIndex)   rst_ctr_tagtable <- mkReg(0);
    Reg#(Bool) bimodal_rst_complete <- mkReg(False);
    Reg#(Bool) tagtable_rst_complete <- mkReg(False);

    //D Wires for Compressed Histories
    Wire#(Vector#(TSub#(`NUMTAGTABLES,1), CSR)) dw_index_csr <- mkDWire(unpack(0));
    Wire#(Vector#(2, CSR)) dw_tag1_csr1 <- mkDWire(unpack(0));
    Wire#(Vector#(2, CSR)) dw_tag1_csr2 <- mkDWire(unpack(0));
    Wire#(Vector#(2, CSR)) dw_tag2_csr1 <- mkDWire(unpack(0));
    Wire#(Vector#(2, CSR)) dw_tag2_csr2 <- mkDWire(unpack(0));

      //display Register
    Reg#(Bool) display <- mkReg(False);

        //for file write to get simulation result
    `ifdef TAGE_DISPLAY
        let fh <- mkReg(InvalidFile) ;
        String dumpFile = "sim_results.txt" ;
        
        rule rl_fdisplay(fh == InvalidFile);
            File lfh <- $fopen( dumpFile, "w" ) ;
            if ( lfh == InvalidFile )
            begin
                $display("cannot open %s", dumpFile);
                $finish(0);
            end
            fh <= lfh ;
        endrule
    `endif

    `ifdef TAGE_DISPLAY
      function Action check_u_counters(Vector#(`NUMTAGTABLES,TagEntry) entries);
        action
          Integer found = 0;
          for (Integer i=0; i<`NUMTAGTABLES; i=i+1) begin
            if (entries[i].uCtr > 0) begin
                found = found + 1;
            end
          end
          `ifdef TAGE_DISPLAY
          if (display) begin
            $fdisplay(fh, "Found value = %d", found);
          end
          `endif
          if(found == `NUMTAGTABLES) begin
          `ifdef TAGE_DISPLAY
            $fdisplay(fh, "Found value = %d", found);
            $fdisplay(fh, "Found all u>0", fshow(entries));
            $fdisplay(fh, "\n");
          `endif
          end
        endaction
      endfunction
    `endif
    

    function initialise_CompHist ();
      action 
        for (Integer i = 0; i < 3; i = i+1) begin
            reg_index_csr[i] <= tagged CSR_index 0;
            if( i < 2) begin
              reg_tag1_csr1[i] <= tagged CSR1_tag1 0;              
              reg_tag1_csr2[i] <= tagged CSR2_tag1 0;
              reg_tag2_csr1[i] <= tagged CSR1_tag2 0;
              reg_tag2_csr2[i] <= tagged CSR2_tag2 0;
            end
        end
      endaction
    endfunction


    function ActionValue#(Bit#(`TABLE_LEN)) update_individualCSRs(Bit#(1) geometric_max,Bit#(1) outcome, CSR fold_history, Int#(10) geomLength, Int#(10) targetLength);
      actionvalue
        Bit#(`TABLE_LEN) bits_fold_history = 0;

        // $display("Geomlength = %d, TargetLength = %d",csr.geomLength,csr.targetLength);

        case (fold_history) matches
          tagged CSR_index  .ind  : bits_fold_history = ind;
          tagged CSR1_tag1  .tag_11: bits_fold_history = zeroExtend(tag_11);
          tagged CSR1_tag2  .tag_12: bits_fold_history = zeroExtend(tag_12);
          tagged CSR2_tag1  .tag_21: bits_fold_history = zeroExtend(tag_21);
          tagged CSR2_tag2  .tag_22: bits_fold_history = zeroExtend(tag_22);
        endcase

        // $display("\n\nInitial CSR value: %b", bits_fold_history);
        let index = geomLength % targetLength;
        let t_len = targetLength;
        let v_msb = bits_fold_history[t_len-1];
        bits_fold_history = (bits_fold_history << 1);

        // $display("Circular Shifted CSR value: %b", bits_fold_history);


        bits_fold_history[0] = bits_fold_history[0] ^ outcome ^ v_msb;

        // $display("Outcome = %b", outcome);
        // $display("Outcome added, CSR value: %b", bits_fold_history);

        // $display("Geometric max: %b", geometric_max);  
        // $display("Geometric max index: %d", index);
        bits_fold_history[index] = bits_fold_history[index] ^ geometric_max;

        // $display("Final CSR value: %b\n\n", bits_fold_history);


        return bits_fold_history;
      endactionvalue
      
    endfunction

    function Action updateCSRs (Bit#(1) ghr_bits[], Bool is_speculatve);
      action
        Integer glen[4] = { `GHR1, `GHR2, `GHR3, `GHR4 };
        if(is_speculatve) begin
          for (Integer i = 0; i < 3; i= i+1) begin
            let csr <- update_individualCSRs(ghr_bits[i+1], ghr_bits[4], reg_index_csr[i], fromInteger(glen[i+1]), `TABLE_LEN);
            reg_index_csr[i] <= tagged CSR_index csr;
            if( i < 2) begin
              let tag_csr <- update_individualCSRs(ghr_bits[i], ghr_bits[4], reg_tag1_csr1[i], fromInteger(glen[i]), fromInteger(`TAG1_CSR1_SIZE));
              reg_tag1_csr1[i] <= tagged CSR1_tag1 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i], ghr_bits[4], reg_tag1_csr2[i], fromInteger(glen[i]), fromInteger(`TAG1_CSR2_SIZE));
              reg_tag1_csr2[i] <= tagged CSR2_tag1 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i+2], ghr_bits[4], reg_tag2_csr1[i], fromInteger(glen[i+2]), fromInteger(`TAG2_CSR1_SIZE));
              reg_tag2_csr1[i] <= tagged CSR1_tag2 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i+2], ghr_bits[4], reg_tag2_csr2[i], fromInteger(glen[i+2]), fromInteger(`TAG2_CSR2_SIZE));
              reg_tag2_csr2[i] <= tagged CSR2_tag2 truncate(tag_csr);
            end
          end
        end
        else begin
          for (Integer i = 0; i < 3; i= i+1) begin
            let csr <- update_individualCSRs(ghr_bits[i+1], ghr_bits[4], dw_index_csr[i], fromInteger(glen[i+1]), `TABLE_LEN);
            reg_index_csr[i] <= tagged CSR_index csr;
            if( i < 2) begin
              let tag_csr <- update_individualCSRs(ghr_bits[i], ghr_bits[4], dw_tag1_csr1[i], fromInteger(glen[i]), fromInteger(`TAG1_CSR1_SIZE));
              reg_tag1_csr1[i] <= tagged CSR1_tag1 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i], ghr_bits[4], dw_tag1_csr2[i], fromInteger(glen[i]), fromInteger(`TAG1_CSR2_SIZE));
              reg_tag1_csr2[i] <= tagged CSR2_tag1 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i+2], ghr_bits[4], dw_tag2_csr1[i], fromInteger(glen[i+2]), fromInteger(`TAG2_CSR1_SIZE));
              reg_tag2_csr1[i] <= tagged CSR1_tag2 truncate(tag_csr);
              tag_csr <- update_individualCSRs(ghr_bits[i+2], ghr_bits[4], dw_tag2_csr2[i], fromInteger(glen[i+2]), fromInteger(`TAG2_CSR2_SIZE));
              reg_tag2_csr2[i] <= tagged CSR2_tag2 truncate(tag_csr);
            end
          end
      end
          
      endaction
    endfunction

    function Bit#(`TABLE_LEN) compFoldIndex(ProgramCounter pc, PathHistory v_phr, TableNo ti);
      Bit#(`TABLE_LEN) index = 0;
      case (ti)
        3'b000 :  
                  index = pc[`BIMODAL_LEN:0]; 
        3'b001 :  
                  index = pc[9:0] ^ pc[19:10] ^ pc[29:20] ^ pc[39:30] ^ pc[49:40] ^ pc[59:50] ^ zeroExtend(pc[63:60]) ^ 
                          ghr[9:0] ^ v_phr[9:0] ^ zeroExtend(v_phr[15:10]);
        3'b010 : 
                  index = pc[9:0] ^ pc[19:10] ^ pc[29:20] ^ pc[39:30] ^ pc[49:40] ^ pc[59:50] ^ zeroExtend(pc[63:60]) ^
                          truncate(pack(reg_index_csr[0])) ^ v_phr[9:0] ^ zeroExtend(v_phr[15:10]); 
        3'b011 : 
                  index = pc[9:0] ^ pc[19:10] ^ pc[29:20] ^ pc[39:30] ^ pc[49:40] ^ pc[59:50] ^ zeroExtend(pc[63:60]) ^
                          truncate(pack(reg_index_csr[1])) ^ v_phr[9:0] ^ zeroExtend(v_phr[15:10]);
        3'b100 : 
                  index = pc[9:0] ^ pc[19:10] ^ pc[29:20] ^ pc[39:30] ^ pc[49:40] ^ pc[59:50] ^ zeroExtend(pc[63:60]) ^
                          truncate(pack(reg_index_csr[2])) ^ v_phr[9:0] ^ zeroExtend(v_phr[15:10]);
      endcase
      return index;
    endfunction

    function Bit#(`TAG2_CSR1_SIZE) compFoldTag(ProgramCounter pc, TableNo ti);
      Bit#(`TAG2_CSR1_SIZE) comp_tag_table = 0;
      case (ti) 
        3'b001 :  begin
                    Bit#(`TAG1_CSR1_SIZE) csr_1 = truncate(pack(reg_tag1_csr1[0]));
                    Bit#(`TAG1_CSR2_SIZE) csr_2 = truncate(pack(reg_tag1_csr2[0]));
                    comp_tag_table = zeroExtend(pc[7:0] ^ csr_1 ^ (zeroExtend(csr_2) << 1)) ;
                  end
        3'b010 :  begin
                    Bit#(`TAG1_CSR1_SIZE) csr_1 = truncate(pack(reg_tag1_csr1[1]));
                    Bit#(`TAG1_CSR2_SIZE) csr_2 = truncate(pack(reg_tag1_csr2[1]));
                    comp_tag_table = zeroExtend(pc[7:0] ^ csr_1 ^ (zeroExtend(csr_2) << 1)) ;
                  end
        3'b011 :  begin 
                    Bit#(`TAG2_CSR1_SIZE) csr_1 = truncate(pack(reg_tag2_csr1[0]));
                    Bit#(`TAG2_CSR2_SIZE) csr_2 = truncate(pack(reg_tag2_csr2[0]));
                    comp_tag_table = zeroExtend(pc[8:0] ^ csr_1 ^ (zeroExtend(csr_2) << 1)) ;  
                  end
        3'b100 :  begin
                    Bit#(`TAG2_CSR1_SIZE) csr_1 = truncate(pack(reg_tag2_csr1[1]));
                    Bit#(`TAG2_CSR2_SIZE) csr_2 = truncate(pack(reg_tag2_csr2[1]));
                    comp_tag_table = zeroExtend(pc[8:0] ^ csr_1 ^ (zeroExtend(csr_2) << 1)) ;
                  end
      endcase
      return comp_tag_table;
    endfunction

    

    rule rl_reset(rg_resetting);
      if (rst_ctr_b <= bimodal_max) begin
        bimodal.upd(rst_ctr_b,unpack(2'b0)); 
        rst_ctr_b <= rst_ctr_b + 1;
      end
      if (rst_ctr_tagtable < table_max) begin
        table_0.upd(rst_ctr_tagtable, unpack(15'b0));
        table_1.upd(rst_ctr_tagtable, unpack(15'b0));
        table_2.upd(rst_ctr_tagtable, unpack(15'b0));
        table_3.upd(rst_ctr_tagtable, unpack(15'b0));
        rst_ctr_tagtable <= rst_ctr_tagtable + 1;
      end
      if (rst_ctr_b == bimodal_max-1) bimodal_rst_complete <= True;
      if (rst_ctr_tagtable == table_max-1) tagtable_rst_complete <= True;      
      if (bimodal_rst_complete && tagtable_rst_complete) begin
        rg_resetting <= False;
        initialise_CompHist();

        `ifdef TAGE_DISPLAY
            if (display) begin
                $fdisplay(fh, "\nReset Over!",cur_cycle);
            end
        `endif
      end
    endrule

    //rule to update the GHR and PHR when actualoutcome is obtained.
    rule rl_update_GHR_PHR (!rg_resetting);
      PathHistory t_phr = 0;
      GlobalHistory t_ghr = 0;
      // Misprediction if occured, reconstruct GHR and PHR 
      if (dw_mispred == 1'b1) begin
        t_ghr = dw_ghr;
        t_ghr = update_GHR(t_ghr, dw_outcome);
        t_phr = dw_phr;

        `ifdef TAGE_DISPLAY
            if (display) begin
                $fdisplay(fh, "Speculatively updated GHR:(reflects on internal GHR in next cycle) %b", t_ghr);
                $fdisplay(fh, "Speculatively updated PHR:(reflects on internal GHR in next cycle) %b", t_phr);
            end
        `endif

        Bit#(1) ghr_bits[5] = {t_ghr[`GHR1], t_ghr[`GHR2], t_ghr[`GHR3], dw_ghr[`GHR4-1], t_ghr[0]};  //130th bit of ghr before updation
        updateCSRs(ghr_bits, False);
      end
      else if(dw_pred_over) begin
        t_ghr = update_GHR(ghr, dw_pred);
        t_phr = update_PHR(phr, dw_pc_bit);
        `ifdef TAGE_DISPLAY
            if (display) begin
                $fdisplay(fh, "Speculatively updated GHR:(reflects on internal GHR in next cycle) %b", t_ghr);
                $fdisplay(fh, "Speculatively updated PHR:(reflects on internal GHR in next cycle) %b", t_phr);
            end
        `endif
        
        Bit#(1) ghr_bits[5] = {t_ghr[`GHR1], t_ghr[`GHR2], t_ghr[`GHR3], ghr[`GHR4-1], t_ghr[0]};
        updateCSRs(ghr_bits, True);
      end
      ghr <= t_ghr;
      phr <= t_phr;
    endrule

    
    method Action computePrediction(ProgramCounter pc) if (!rg_resetting);
      `ifdef TAGE_DISPLAY
        if (display) begin
            $fdisplay(fh, "\n\nIn computePrediction method", cur_cycle);
            $fdisplay(fh, "\nCurrent Program Counter Value: %b", pc, cur_cycle);
        end
      `endif
      

      //tags
      Tag computedTag[`NUMTAGTABLES];
      for (Integer i = 0; i < `NUMTAGTABLES; i = i+1) begin
        if(i<2)
        computedTag[i] = tagged Tag1 0;
        else
        computedTag[i] = tagged Tag2 0;
      end
      
      //indexes
      BimodalIndex bimodal_index = 0;
      TagTableIndex tagTable_indexes[`NUMTAGTABLES] = { 0, 0, 0 ,0 };

      //variable to store temporary prediction packet
      PredictionPacket t_pred_pkt = unpack(0);

      //updating PHR in temporary prediction packet
      t_pred_pkt.phr = update_PHR(phr, pc[2]);

    
      for (Integer i = 0; i < 3; i=i+1) begin
        t_pred_pkt.index_csr[i] = reg_index_csr[i];
        if(i<2) begin
          t_pred_pkt.tag1_csr1[i] = reg_tag1_csr1[i];
          t_pred_pkt.tag1_csr2[i] = reg_tag1_csr2[i];
          t_pred_pkt.tag2_csr1[i] = reg_tag2_csr1[i];
          t_pred_pkt.tag2_csr2[i] = reg_tag2_csr2[i];
        end
      end

      //calling index computation function for each table and calling tag computation function for each table
      bimodal_index = compFoldIndex(pc,t_pred_pkt.phr,3'b000);
      t_pred_pkt.bimodal_index = bimodal_index;
      for (Integer i = 0; i < 4; i=i+1) begin
        TableNo tNo = fromInteger(i+1);
        tagTable_indexes[i] = compFoldIndex(pc,t_pred_pkt.phr,tNo);
        t_pred_pkt.tagTable_index[i] = tagTable_indexes[i];
        if(i<2) begin
          computedTag[i] = tagged Tag1 truncate(compFoldTag(pc,tNo));
          t_pred_pkt.tableTag[i] = computedTag[i];
        end
        else begin
          computedTag[i] = tagged Tag2 truncate(compFoldTag(pc,tNo));
          t_pred_pkt.tableTag[i] = computedTag[i];
        end
      end
      `ifdef TAGE_DISPLAY
        if (display) begin
          $fdisplay(fh, "\n\nStructures before prediction", cur_cycle);
          $fdisplay(fh, "Computed Tags of T1    ", fshow(computedTag[0]),cur_cycle);
          $fdisplay(fh, "Computed Tags of T2    ", fshow(computedTag[1]),cur_cycle);
          $fdisplay(fh, "Computed Tags of T3    ", fshow(computedTag[2]),cur_cycle);
          $fdisplay(fh, "Computed Tags of T4    ", fshow(computedTag[3]),cur_cycle);
          $fdisplay(fh, "Computed Bimodal index     ", fshow(bimodal_index),cur_cycle);
          $fdisplay(fh, "Computed Index of Tagged Table of T1   ", fshow(tagTable_indexes[0]),cur_cycle);
          $fdisplay(fh, "Computed Index of Tagged Table of T2   ", fshow(tagTable_indexes[1]),cur_cycle);
          $fdisplay(fh, "Computed Index of Tagged Table of T3   ", fshow(tagTable_indexes[2]),cur_cycle);
          $fdisplay(fh, "Computed Index of Tagged Table of T4   ", fshow(tagTable_indexes[3]),cur_cycle);
          $fdisplay(fh, "Current internal PHR = %b", phr, cur_cycle);
          $fdisplay(fh, "Current internal GHR = %b", ghr, cur_cycle);
        end
      `endif

      //comparison of tag with the longest history table, getting prediction from it and alternate prediction from second longest tag matching table 
      t_pred_pkt.tableNo = 3'b000;
      t_pred_pkt.altpred = bimodal.sub(bimodal_index).ctr[1];
      t_pred_pkt.pred = bimodal.sub(bimodal_index).ctr[1];
      t_pred_pkt.ctr[0] = zeroExtend(bimodal.sub(bimodal_index).ctr);
      Bool matched = False;
      Bool altMatched = False;
      for (Integer i = 3; i >= 0; i=i-1) begin
        if(tagTables[i].sub(tagTable_indexes[i]).tag == computedTag[i] && !matched) begin
          t_pred_pkt.ctr[i+1] = tagTables[i].sub(tagTable_indexes[i]).ctr;
          t_pred_pkt.pred = tagTables[i].sub(tagTable_indexes[i]).ctr[2];
          t_pred_pkt.tableNo = fromInteger(i+1); 
          t_pred_pkt.uCtr[i] = tagTables[i].sub(tagTable_indexes[i]).uCtr;        
          matched = True;
        end
        else if(tagTables[i].sub(tagTable_indexes[i]).tag == computedTag[i] && matched && !altMatched) begin
          t_pred_pkt.altpred = tagTables[i].sub(tagTable_indexes[i]).ctr[2];
          altMatched = True;
        end
      end
      
      dw_pred <= t_pred_pkt.pred;              //setting RWire for corresponding GHR updation in the rule
      dw_pc_bit<=pc[2];

      t_pred_pkt.ghr = ghr;
      
      pred_pkt <= t_pred_pkt;                     //assigning temporary prediction packet to prediction packet vector register
      `ifdef TAGE_DISPLAY
        if (display) begin
          $fdisplay(fh, "\n\nStructures after prediction", cur_cycle);
          $fdisplay(fh, "Computed Tags of T1    ", fshow(computedTag[0]),cur_cycle);
          $fdisplay(fh, "Computed Tags of T2    ", fshow(computedTag[1]),cur_cycle);
          $fdisplay(fh, "Computed Tags of T3    ", fshow(computedTag[2]),cur_cycle);
          $fdisplay(fh, "Computed Tags of T4    ", fshow(computedTag[3]),cur_cycle);
          $fdisplay(fh, "Computed Bimodal index     ", fshow(bimodal_index),cur_cycle);
          $fdisplay(fh, "Computed Index of Tagged Table of T1   ", fshow(tagTable_indexes[0]),cur_cycle);
          $fdisplay(fh, "Computed Index of Tagged Table of T2   ", fshow(tagTable_indexes[1]),cur_cycle);
          $fdisplay(fh, "Computed Index of Tagged Table of T3   ", fshow(tagTable_indexes[2]),cur_cycle);
          $fdisplay(fh, "Computed Index of Tagged Table of T4   ", fshow(tagTable_indexes[3]),cur_cycle);
          $fdisplay(fh, "Prediction Packet     ", fshow(t_pred_pkt), cur_cycle);
          $fdisplay(fh, "\nPrediction Over!", cur_cycle);
          $fdisplay(fh, "\n===============================================================================================",cur_cycle);
        end
      `endif
      dw_pred_over <= True;           
    endmethod


    method Action updateTablePred(UpdationPacket upd_pkt) if (!rg_resetting);  
        `ifdef TAGE_DISPLAY
            if (display) begin
                $fdisplay(fh, "\n===============================================================================================");
                $fdisplay(fh, "\n\nIn updation method");

                $fdisplay(fh, "\nBranch Outcome = %b", upd_pkt.actualOutcome);
                $fdisplay(fh, "Checkpointed GHR = %b\n",upd_pkt.ghr);
                $fdisplay(fh, "\n\nStructures before updation", cur_cycle);
                $fdisplay(fh, "Tags of T1, T2, T3, T4 in Updation Packet    ", fshow(upd_pkt.tableTag), cur_cycle);
                $fdisplay(fh, "Bimodal index in Updation Packet     ", fshow(upd_pkt.bimodal_index), cur_cycle);
                $fdisplay(fh, "Index of Tagged Tables in Updation Packet    ", fshow(upd_pkt.tagTable_index), cur_cycle);
                $fdisplay(fh, "Updation Packet     ", fshow(upd_pkt), cur_cycle);
                $fdisplay(fh, "Updation Packet's PHR = %b", upd_pkt.phr, cur_cycle);
                $fdisplay(fh, "Updation Packet's GHR = %b", upd_pkt.ghr, cur_cycle);
            end
        `endif
        dw_ghr <= upd_pkt.ghr;
        dw_phr <= upd_pkt.phr;
        dw_outcome <= upd_pkt.actualOutcome;
        dw_mispred <= upd_pkt.mispred;


        dw_index_csr <= upd_pkt.index_csr;
        
        dw_tag1_csr1  <= upd_pkt.tag1_csr1;
        
        dw_tag1_csr2  <= upd_pkt.tag1_csr2;
        
        dw_tag2_csr1  <= upd_pkt.tag2_csr1;
        
        dw_tag2_csr2  <= upd_pkt.tag2_csr2;
        
        //store the indexes of each entry of predictor tables from the updation packet
        //Store the corresponding indexed entry whose index is obtained from the updation packet

        
        BimodalEntry bimodal_entry = unpack(0);
        bimodal_entry.ctr = truncate(upd_pkt.ctr[0]);        //size of uctr field is 3 bits
        Vector#(`NUMTAGTABLES,TagEntry) tagTable_entries = unpack(0);
        for (Integer i=0; i < `NUMTAGTABLES; i=i+1) begin
            tagTable_entries[i].ctr = upd_pkt.ctr[i+1];
            tagTable_entries[i].uCtr = upd_pkt.uCtr[i];
            tagTable_entries[i].tag = upd_pkt.tableTag[i];
        end
        


        TableNo tagtableNo = upd_pkt.tableNo-1;

        

        //store the actual outcome from the updation packet
        ActualOutcome outcome = upd_pkt.actualOutcome;



        //Updation of usefulness counter
        /* Usefulness counter is updated if the final prediction is different from alternate 
        prediction, u is incremented if the prediction is correct u is decremented otherwise */


        if (upd_pkt.pred != upd_pkt.altpred) begin
            if (upd_pkt.mispred == 1'b0 && tagtableNo != 3'b000)
                tagTable_entries[tagtableNo].uCtr = upd_pkt.uCtr[tagtableNo] + 2'b1;
            else
                tagTable_entries[tagtableNo].uCtr = upd_pkt.uCtr[tagtableNo] - 2'b1;
        end

        // updation of provider component's prediction counter
        /* Provider component's prediction counter is incremented if actual outcome is TAKEN and decremented if actual outcome is NOT TAKEN */

        if(upd_pkt.actualOutcome == 1'b1) begin
            if(upd_pkt.tableNo == 3'b000)
                bimodal_entry.ctr = (upd_pkt.ctr[0] < 3'b11) ? truncate((upd_pkt.ctr[0] + 3'b1)) : 2'b11 ;
            else
                tagTable_entries[tagtableNo].ctr = (upd_pkt.ctr[tagtableNo+1] < 3'b111 )?(upd_pkt.ctr[tagtableNo+1] + 3'b1): 3'b111;
        end
        else begin
            if(upd_pkt.tableNo == 3'b000)
                bimodal_entry.ctr = (upd_pkt.ctr[0] < 3'b11)? truncate((upd_pkt.ctr[0] - 3'b1)) : 2'b00;
            else
                tagTable_entries[tagtableNo].ctr = (upd_pkt.ctr[tagtableNo+1] > 3'b000)?(upd_pkt.ctr[tagtableNo+1] - 3'b1): 3'b000;
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
        
        `ifdef TAGE_DISPLAY
            check_u_counters(tagTable_entries);
        `endif

        if (upd_pkt.mispred == 1'b1) begin
            case (upd_pkt.tableNo)
                3'b000 :    tagTable_entries = allocate_entry(tagTable_entries, 0, upd_pkt.tableTag, upd_pkt.actualOutcome);
                3'b001 :    tagTable_entries = allocate_entry(tagTable_entries, 1, upd_pkt.tableTag, upd_pkt.actualOutcome);
                3'b010 :    tagTable_entries = allocate_entry(tagTable_entries, 2, upd_pkt.tableTag, upd_pkt.actualOutcome);
                3'b011 :    tagTable_entries = allocate_entry(tagTable_entries, 3, upd_pkt.tableTag, upd_pkt.actualOutcome);
            endcase
        end
                        
        
        //Assigning back the corresponding entries to the prediction tables.
        bimodal.upd(upd_pkt.bimodal_index,bimodal_entry);
        for(Integer i = 0 ; i < `NUMTAGTABLES; i = i+1)
            tagTables[i].upd(upd_pkt.tagTable_index[i], tagTable_entries[i]);
        `ifdef TAGE_DISPLAY
            if (display) begin
                $fdisplay(fh, "\n\nStructures after updation", cur_cycle);
                $fdisplay(fh, "Tags of T1, T2, T3, T4 in Updation Packet    ", fshow(upd_pkt.tableTag), cur_cycle);
                $fdisplay(fh, "Bimodal index in Updation Packet     ", fshow(upd_pkt.bimodal_index), cur_cycle);
                $fdisplay(fh, "Index of Tagged Tables in Updation Packet    ", fshow(upd_pkt.tagTable_index), cur_cycle);
                $fdisplay(fh, "Updation Packet     ", fshow(upd_pkt), cur_cycle);
                $fdisplay(fh, "Updation Packet's PHR = %b", upd_pkt.phr, cur_cycle);
                $fdisplay(fh, "Updation Packet's GHR = %b", upd_pkt.ghr, cur_cycle);
                $fdisplay(fh, "Updation Over!");
            end
        `endif
    endmethod

    method PredictionPacket output_packet(); //method that outputs the prediction packet
        return pred_pkt;
    endmethod

    method Action displayInternal(Bool start_display);
        display <= start_display;
    endmethod

  endmodule

endpackage