# TAGE Branch Predictor Algorithm
Tagged Geometric (TAGE) History length is a conditional branch predictor that makes use of several predictor components or predictor tables. It uses geometric history length as in OGEHL predictor and (partially) tagged tables as in PPM-like predictor. (They are different efficient predictors from which TAGE was derived)

## Architecture
TAGE consists of two types of predictors - bimodal predictor and tagged table predictors.

| Predictor Name | Function | Fields in Each Entry of Table |
|---------|----------|----------|
| Bimodal Predictor (T0) | In charge of providing basic prediction | 2 bit saturation counter |
| Tagged Table Predictors (T1, T2, T3, T4) | In charge of providing prediction in the case of tag match | 3 bit signed saturation counter, Unsigned Usefulness 2 bit Counter, Tag |

