# `Type_TAGE.bsv`

The file contains all the user defined types for the TAGE hardware structure. Also, included the function for calculating the index of table predictors and the tags of Tagged Table predictors.

| Type Name | Function | Remarks |
| --------- | -------- |
| `Program Counter`| Type of Program Counter|Bit Type |
| `Global History` | Type of Global History Register | should be of but length  GHR+1|
| `TableNo` | Index of index of each Tagged Table Predictors staring from 0 | 00,01,10,11 |
| `BimodalIndex` | Type of index of each entry in Bimodal Predictor Table | Bit Type |
| `TagTableIndex` | Type of index of each entry in Tagged Table Predictors | Bit Type |
| `BimodalCtr` | Type of Prediction Counter in Bimodal Predictor Table | Bit Type |
| `TagTableCtr` | Type of Prediction Counter in Tagged Table Predictor  Tables | Bit Type |
| `TableTag1` | Type of tag1 in Tagged Predictor Tables | Bit Type, Tags of T1 and T2 Tables |
| `TableTag2` | Type of tag2 in Tagged Predictor Tables | Bit Type, Tags of T3 and T4 Tables |
| `UsefulCtr` | Type of Usefulness Counter in each Tagged Predictor Tables | Bit Type |
|`ActualOutcome` | Type of Actual Outcome of Branch Instruction | Bit Type |
|`Prdiction` | Type of Prediction from the TAGE Predictor | Bit Type |
|`AltPrediction` | Type of Alternate Prediction from the TAGE Predictor | Bit Type |
| `Misprediction` | Type of Misprediction from the TAGE Predictor | Bit Type |
| `GeomLength` | Type of Geometric Lengths from each Tagged Predictor Tables | Bit Type, values can be 5,15,44,130 |
| `TargetLength` | Type of the target lengths to which the index or tag needs to be converted to | Bit Type |
| `PathHistory` | Type of Path History Register | Bit Type |

### Defined  Structure Types

| Name | Type | Fields |Remarks |
|-------| ------ |------| ------ |
| `Tag` | Union | `Tag1`, `Tag2` | Based on the size of initialisation Tags of required size will be chosen |
| `TagEntry`  | Struct | prediction counter (`ctr`), usefulness counter (`uctr`), `tag` | Type of Each entry of Tagged Predictor Tables |
| `BimodalEntry` | Struct |prediction counter (`ctr`) | Type of Each entry in Bimodal Predictor Table |

#### Output Structure Type - `PredictionPacket`

| Field Names | Type | Function |
| ------ | ------| ---------|
|`bimodal_index` | BimodalIndex | stores index of entry in Bimodal Predictor Table which provided prediction |
|`tagTable_index` | Vector of TagTableIndex type | stores all the entries in tagged predictor indexes which provided prediction |
| `tableTag` | Vector of Tag type | stores the tags of all entries which provided prediction |
| `uCtr` | Vector of Usefulness Counter type | stores the uCtr of all entries in tagged predictor tables which provided prediction |
| `ctr` | Vector of Prediction counters type | stores all the prediction counters of entries in predictor tables which provided prediction |
| `ghr` | GlobalHistory | stores the GHR used for computing prediction of that branch |
| `pred` | Prediction | stores the prediction of that branch for which the Prediction Packet was made |
| `tableNo` | TableNo | stores the table number of the table which gave final prediction |
| `altpred` |  AltPrediction | stored the alternate prediction, that is prediction from table having second longest history and which has tag match |
| `phr` | PathHistory | stored the PHR used for computing prediction of that branch |

#### Input Updating Structure Type - `UpdationPacket`

The fields in the Updation Packet is same as Prediction Packet used for updating the Table Predictors after obtaining the actual outcome of that branch for which the updation has to be made.

The additional fields required in the `UpdationPacket` are as follows :

| Field Names | Type | Function |
| ------ | ------| ---------|
|`mispred` | Misprediction | stores the prediction is correct or not, 1 for mispredicted and 0 for right prediction |
| `actualOutcome` | ActualOutcome | stored the actual outcome of that branch which is obtained at the instruction execution stage |

### Simulation Structure - `TableCounters`

For counting the number of predictions and mispredictions from each predictor tables.

| Field Name | Type | Function |
| -------| ---------| -------|
| `predictionCtr` | Integer | Stores the number of correction predictions |
| `mispredictionCtr` | Integer | Stores the number of incorrect predictions |

## Functions







