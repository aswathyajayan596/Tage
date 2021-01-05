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
      method Action displayInternal(Bool start_display);
  endinterface

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

      Vector#(`NUMTAGTABLES, Reg#(CompressedHist)) indexComp  <-  replicateM(mkReg(unpack(0)));
      Vector#(`NUMTAGTABLES, Reg#(CompressedHist)) tagComp1   <-  replicateM(mkReg(unpack(0)));
      Vector#(`NUMTAGTABLES, Reg#(CompressedHist)) tagComp2   <-  replicateM(mkReg(unpack(0)));
      
      RegFile#(TagTableIndex, TagEntry) tagTables[`NUMTAGTABLES] = {table_0, table_1, table_2, table_3}; //array of Tagged table predictors  
      
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

      Reg#(Bool)     rg_resetting <- mkReg (True);
      Reg#(BimodalIndex)   rst_ctr_b <- mkReg(0);
      Reg#(TagTableIndex)   rst_ctr_tagtable <- mkReg(0);
      Reg#(Bool) bimodal_rst_complete <- mkReg(False);
      Reg#(Bool) tagtable_rst_complete <- mkReg(False);

      //D Wires for Compressed Histories
      Wire#(Vector#(`NUMTAGTABLES, CompressedHist)) dw_index_compHist <- mkDWire(unpack(0));
      Wire#(Vector#(`NUMTAGTABLES, CompressedHist)) dw_tag_compHist1 <- mkDWire(unpack(0));
      Wire#(Vector#(`NUMTAGTABLES, CompressedHist)) dw_tag_compHist2 <- mkDWire(unpack(0));
      

      function initialise_CompHist ();
  
          action 
              
              Integer geometric[4] = {`GHR1, `GHR2 , `GHR3, `GHR4};
              CompressedHist index[4];
              CompressedHist tag1[4];
              CompressedHist tag2[4];
              Bit#(32) b_index[4];
              Bit#(32) b_tag1[4];
              Bit#(32) b_tag2[4];

              for (Integer i = 0; i < 4; i=i+1) begin
              b_index[i] = fromInteger(geometric[i] % `TABLE_LEN);
              b_tag1[i]  = fromInteger(geometric[i] % `TAG1_SIZE);
              b_tag2[i]  = fromInteger(geometric[i] % `TAG2_SIZE);
              end
              

              for (Integer i = 0; i < 4; i=i+1) begin
              
              index[i] =  CompressedHist { geomLength: fromInteger(geometric[i]), targetLength: `TABLE_LEN, compHist: unpack(0), bmax_index: b_index[i]};
              tag1[i]  =  CompressedHist { geomLength: fromInteger(geometric[i]), targetLength: `TAG1_SIZE, compHist: unpack(0), bmax_index: b_tag1[i]};
              tag2[i]  =  CompressedHist { geomLength: fromInteger(geometric[i]), targetLength: `TAG2_SIZE, compHist: unpack(0), bmax_index: b_tag2[i]};
              indexComp[i] <= index[i];
              tagComp1[i]  <= tag1[i];
              tagComp2[i]  <= tag2[i];

              end

          endaction

      endfunction

      function ActionValue#(Bit#(64)) update_individualCompHist(Bit#(1) geometric_max,Bit#(1) outcome, CompressedHist index_or_tag);

          actionvalue 
      
              Bit#(64) compressed_history;
              compressed_history = index_or_tag.compHist;

            //   $display("\nInitial Compressed History: %b", compressed_history);
              let index = index_or_tag.bmax_index;
              let v_msb = msb(compressed_history);
              compressed_history = (compressed_history << 1);
              let t_len = index_or_tag.targetLength;
              compressed_history = compressed_history[t_len-1:0];
              compressed_history[0] = v_msb;

            //   $display("Circcular Shifted Compressed History: %b", compressed_history);


              compressed_history[0] = compressed_history[0] ^ outcome;

            //   $display("Outcome added, Compressed History: %b", compressed_history);

            //   $display("Geometric max: %b", geometric_max);  
              compressed_history[index] = compressed_history[index] ^ geometric_max;

            //   $display("Final Compressed History: %b", compressed_history);
              return compressed_history;

          endactionvalue
          
      endfunction

      function Action updateCompHists (Bit#(131) t_ghr);
          action
              for (Bit#(3) i=0; i < 4; i=i+1) begin
            //   $display ("\nIndex updation");
              Bit#(64) t_indexComp <- update_individualCompHist(t_ghr[`TABLE_LEN],t_ghr[0], indexComp[i]);
            //   $display ("\nTag1 updation");
              Bit#(64) t_tagComp1 <- update_individualCompHist(t_ghr[`TAG1_SIZE], t_ghr[0], tagComp1[i]);
            //   $display ("\nTag2 updation");
              Bit#(64) t_tagComp2 <- update_individualCompHist(t_ghr[`TAG2_SIZE], t_ghr[0], tagComp2[i]);

              indexComp[i].compHist <= t_indexComp;
              tagComp1[i].compHist <= t_tagComp1;
              tagComp2[i].compHist <= t_tagComp2;
              end
          endaction
      endfunction

      function Bit#(64) compFoldIndex(ProgramCounter pc, PathHistory t_phr, TableNo ti);
          Bit#(64) index = 0;
          if (ti == 3'b000) begin
          index = pc[`BIMODAL_LEN - 1:0];        //13bit pc
          return index;
          end
          else if (ti == 3'b001) begin
          index = pc ^ (pc >> `TABLE_LEN) ^ indexComp[0].compHist ^ zeroExtend(t_phr) ^ (zeroExtend(t_phr) >> `TABLE_LEN); // indexTagPred[0] = PC ^ (PC >> TAGPREDLOG) ^ indexComp[0].compHist ^ PHR ^ (PHR >> TAGPREDLOG);
          return index;
          end
          else if (ti == 3'b010) begin
          index = pc ^ (pc >> (`TABLE_LEN - 1)) ^ indexComp[1].compHist ^ zeroExtend(t_phr) ^ (zeroExtend(t_phr) >> `TABLE_LEN);
          return index;
          end
          else if (ti == 3'b011) begin
          index = pc ^ (pc >> (`TABLE_LEN - 2)) ^ indexComp[2].compHist ^ zeroExtend(t_phr) ^ (zeroExtend(t_phr) >> `TABLE_LEN);
          return index;
          end
          else begin
          index = pc ^ (pc >> (`TABLE_LEN - 3)) ^ indexComp[3].compHist ^ zeroExtend(t_phr) ^ (zeroExtend(t_phr) >> `TABLE_LEN);
          return index;
          end
      endfunction

      function Bit#(64) compFoldTag(ProgramCounter pc, TableNo ti);
        Bit#(64) comp_tag_table = 0;
        if (ti == 3'b001) begin
          comp_tag_table = pc ^ tagComp1[0].compHist ^ (tagComp2[0].compHist << 1) ;
          // tag[i] = PC ^ tagComp[0][i].compHist ^ (tagComp[1][i].compHist << 1);
        end
        else if (ti == 3'b010) begin
          comp_tag_table = pc ^ tagComp1[1].compHist ^ (tagComp2[1].compHist << 1) ;

        end
        else if (ti == 3'b011) begin
          comp_tag_table = pc ^ tagComp1[2].compHist ^ (tagComp2[2].compHist << 1) ;
        end
        else if (ti == 3'b100) begin
          comp_tag_table = pc ^ tagComp1[3].compHist ^ (tagComp2[3].compHist << 1) ;
        end
        return comp_tag_table;
      endfunction

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

      

      rule rl_reset(rg_resetting);

          if (rst_ctr_b <= bimodal_max) begin
              bimodal.upd(rst_ctr_b,unpack(2'b01)); //weakly not taken
              rst_ctr_b <= rst_ctr_b + 1;
          end
          if (rst_ctr_tagtable < table_max) begin
              table_0.upd(rst_ctr_tagtable, unpack(15'b011000000000000));
              table_1.upd(rst_ctr_tagtable, unpack(15'b011000000000000));
              table_2.upd(rst_ctr_tagtable, unpack(15'b011000000000000));
              table_3.upd(rst_ctr_tagtable, unpack(15'b011000000000000));
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
              writeVReg( indexComp, dw_index_compHist);
              writeVReg( tagComp1, dw_tag_compHist1);
              writeVReg( tagComp2, dw_tag_compHist2);
          end
          else if(dw_pred_over) begin
              t_ghr = update_GHR(ghr, dw_pred);
              t_phr = update_PHR(phr, dw_pc);
              `ifdef TAGE_DISPLAY
                  if (display) begin
                      $fdisplay(fh, "Speculatively updated GHR:(reflects on internal GHR in next cycle) %b", t_ghr);
                      $fdisplay(fh, "Speculatively updated PHR:(reflects on internal GHR in next cycle) %b", t_phr);
                  end
              `endif
              updateCompHists(t_ghr);
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
          for (Integer i = 0; i < `NUMTAGTABLES; i = i+1)
              computedTag[i] = tagged Tag1 0;
          
          //indexes
          BimodalIndex bimodal_index = 0;
          TagTableIndex tagTable_indexes[`NUMTAGTABLES] = { 0, 0, 0 ,0 };

          //variable to store temporary prediction packet
          PredictionPacket t_pred_pkt = unpack(0);

          //updating PHR in temporary prediction packet
          t_pred_pkt.phr = update_PHR(phr, pc);

          for (Integer i = 0; i < `NUMTAGTABLES; i=i+1) begin
            t_pred_pkt.index_compHist[i] = indexComp[i];
            t_pred_pkt.tag_compHist1[i] = tagComp1[i];
            t_pred_pkt.tag_compHist2[i] = tagComp2[i];
          end

          


          //calling index computation function for each table and calling tag computation function for each table
          bimodal_index = truncate(compFoldIndex(pc,t_pred_pkt.phr,3'b000));
          t_pred_pkt.bimodal_index = bimodal_index;
          for (Integer i = 0; i < 4; i=i+1) begin
              TableNo tNo = fromInteger(i+1);
              tagTable_indexes[i] = truncate(compFoldIndex(pc,t_pred_pkt.phr,tNo));
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
          dw_pc<=pc;

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

          dw_index_compHist <= upd_pkt.index_compHist;
          dw_tag_compHist1  <= upd_pkt.tag_compHist1;
          dw_tag_compHist2  <= upd_pkt.tag_compHist2;

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