//+------------------------------------------------------------------+
//| The EA finds the high and low from a specified time range, whenever the price breaks
//| the high/low a trade is enterd with a stop loss at high/low                                 
//| Closes all trades at specific time

//| V1.1 Changes the logic to trade a stop run before the entry, 
//| meaning that to short the high needs to be taken before the low and entry
//| stop loss at the high
//+------------------------------------------------------------------+

#include <Trade\Trade.mqh>

//tick and trader
MqlTick currentTick, previousTick;
MqlDateTime timeStructure;
CTrade trade;

static input long    InpMagicNumber = 27321; // magic number 

input int TimeStartHour = 2;                 // time range start hour
input int TimeStartMin = 30;                 // time range start min

input int TimeEndHour = 5;                   // time range end hour
input int TimeEndMin = 30;                   // time range end min


input int EndOfDayHour = 22;                 // end of day hour
input int EndOfDayMin = 30;                  // end of day min

input double InpRiskToReward = 0;            // risk to reward
input double InpRiskPCT = 1;                 // PCT of account to risk

input bool InpCloseTrades = true;            // close all trades on specified time

input bool trailingSL = true;                // trailing SL on/off
input int InpSLBars = 20;                    // range to find swings to move SL to

input bool InpFixed = true;                  // fixed risk or pct of account

bool waitingForHigh = true;                  // polarity of cycle
bool pivotFound = false;                     // used in cycle logic
datetime currentPivot;                       // next date coming
datetime nextPivot;                          // date after that
int icycle = 0;                              // position in the cycle array


int buyCntToday = 0;
int sellCntToday = 0;

double highPrice = 500;
double lowPrice = 0;

datetime timeStart;
datetime timeEnd;

datetime now;
datetime endOfDay;

//v1.1
bool highTaken = false;
bool lowTaken = false;
double lowOfStopRunPrice = 0;
double highOfStopRunPrice = 0;


bool martinGale = false;
input int InpMartingaleThreshold = 3;        //number of losses before martingale strategy kicks in (0=off)
int martingaleMultiplier = 0;

int OnInit()
  {
  
  // set magic number
      trade.SetExpertMagicNumber(InpMagicNumber);
   
return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
  {

   
}

//tester
double OnTester(){
   
   if(TesterStatistics(STAT_TRADES)==0){
      return 0.0;
   }
   if(TesterStatistics(STAT_EQUITY_DDREL_PERCENT)>30){
      return 0.0;
   }
   if(TesterStatistics(STAT_PROFIT)<10000){
      return 0.0;
   }
   double dd = TesterStatistics(STAT_PROFIT);
   double customCriteria = dd;

  return customCriteria;
}

void OnTick()
  {
   // check for new bar open
   if(!IsNewBar()) {return;}
   
   // get tick
   previousTick = currentTick;
   if(!SymbolInfoTick(_Symbol, currentTick)) {Print("Failed to get current tick"); return;}
   
   cycle();
   
   // set time for range   
   setTime();
   
   // find the range
   if(now == timeEnd){
      findRange();
   }
   
   //check for buy 
   if(previousTick.ask < highPrice && currentTick.ask > highPrice && buyCntToday == 0 && waitingForHigh && lowTaken){
      openBuyOrder();
      
   }
   
    //check for sell 
   if(previousTick.bid > lowPrice && currentTick.bid < lowPrice && sellCntToday == 0 && !waitingForHigh && highTaken){
      openSellOrder();
   }
   
   // end of day actions
   if(now == endOfDay){
      endOfDayActions();
   }
   
   // update stoploss
   if(trailingSL){
      updateStopLoss(); }
          
   //martingale
   if(InpMartingaleThreshold > 0){
      martingale(); }
          
          
   string com;
   com= com+"Local Time:"; 
   com= com+(string)now;
   com= com+"\n Start Time:"; 
   com= com+(string)timeStart;  
   com= com+"\n End Time:"; 
   com= com+(string)timeEnd;
   com= com+"\n End of Day Time:"; 
   com= com+(string)endOfDay;                                    
   
   Comment(com);  
   
   if(waitingForHigh){
      if(currentTick.ask < lowPrice){ lowTaken = true;
      Print("low Taken = ", lowTaken);
       
      }
   }  
   
   if(!waitingForHigh){
      if(currentTick.bid > highPrice){ highTaken = true;
      Print("high taken = ", highTaken);
      
      }
   }     
   
}



//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+

// check if we have a bar open tick
bool IsNewBar(){

   static datetime previousTime = 0;
   datetime currentTime = iTime(_Symbol,PERIOD_CURRENT,0);
   if(previousTime!=currentTime){
      previousTime=currentTime;
      return true;
   }
   return false;
}


// set time variables 
void setTime(){
   TimeCurrent(timeStructure);
   timeStructure.sec = 0;
   now = TimeCurrent();
   
   timeStructure.hour = TimeStartHour;
   timeStructure.min = TimeStartMin;
   
   timeStart = StructToTime(timeStructure);
   
   timeStructure.hour = TimeEndHour;
   timeStructure.min = TimeEndMin;
   
   timeEnd = StructToTime(timeStructure);
   
   timeStructure.hour = EndOfDayHour;
   timeStructure.min = EndOfDayMin;
   
   endOfDay = StructToTime(timeStructure);
}

//place buy order
void openBuyOrder(){
         
         //entry
         double entry = currentTick.ask;
         entry = NormalizeDouble(entry,_Digits);
         
         //stop loss
         int timeRangeEndIdx = iBarShift(_Symbol,PERIOD_CURRENT,timeEnd);
         int lowOfStopRunIdx = iLowest(_Symbol,PERIOD_CURRENT,MODE_LOW,timeRangeEndIdx,1);
         lowOfStopRunPrice = iLow(_Symbol,PERIOD_CURRENT,lowOfStopRunIdx);
         double sl = lowOfStopRunPrice - entry*_Point;
         sl = sl - 10*_Point;
         sl = NormalizeDouble(sl,_Digits);
         
         
         //take profit
         double tp = 0; 
         if(InpRiskToReward > 0){
         tp = entry - sl;
         tp = tp * InpRiskToReward;         
         tp = tp + entry;        
         tp = NormalizeDouble(tp,_Digits);         
         } else{ tp = 0;}
         
         //lots
         double lots = CalculateLots(InpRiskPCT,sl - entry);   
         entry = NormalizeDouble(entry,_Digits);
         double lots2=lots*2;
         lots = lots - lots2;
         
         //? useless normalize maybe?
         sl = NormalizeDouble(sl,_Digits);
         
         //martingale strategy
         if(martinGale){
            lots = lots * martingaleMultiplier;}
           
         
         
         //place order
         trade.Buy(lots,_Symbol,currentTick.ask,sl,tp,"buy trade opend");
         
         buyCntToday += 1;
}

//place sell order
void openSellOrder(){
         
         //entry
         double entry = currentTick.bid;
         entry = NormalizeDouble(entry,_Digits);
         
         //stop loss
         int timeRangeEndIdx = iBarShift(_Symbol,PERIOD_CURRENT,timeEnd);
         int lowOfStopRunIdx = iHighest(_Symbol,PERIOD_CURRENT,MODE_HIGH,timeRangeEndIdx,1);
         highOfStopRunPrice = iHigh(_Symbol,PERIOD_CURRENT,lowOfStopRunIdx);
         double sl = highOfStopRunPrice - entry*_Point;
         sl = sl + 10*_Point;
         sl = NormalizeDouble(sl,_Digits);
         
         
         //take profit
         double tp = 0; 
         if(InpRiskToReward > 0){
         tp = entry - sl;
         tp = tp * InpRiskToReward;         
         tp = tp + entry;        
         tp = NormalizeDouble(tp,_Digits);         
         } else{ tp = 0;}
         
         //lots
         double lots = CalculateLots(InpRiskPCT,sl - entry);   
         entry = NormalizeDouble(entry,_Digits);
         
         //martingale strategy
         if(martinGale){
            lots = lots * martingaleMultiplier;}
         
         //place order
         trade.Sell(lots,_Symbol,currentTick.bid,sl,tp,"Sell trade opend");
         
         sellCntToday += 1;
}

//calculate lots
double CalculateLots(double riskPrecent, double slDistance){
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    if(tickSize == 0 || tickValue == 0 || lotStep == 0){
      
      return 0;
    }
    
    double riskMoney = 0;
    if(InpFixed){riskMoney = 10000;}else{riskMoney = AccountInfoDouble(ACCOUNT_BALANCE);}
    
    double moneyLotStep = (slDistance / tickSize) * tickValue * lotStep;
    
    if(moneyLotStep ==0){
    Print("Cannot calculate lot size, ==0");
    return 0;
    }
    double lots = MathFloor(riskMoney / moneyLotStep) * lotStep; 
    
    
    return lots;
  }
  
  double PriceToPoints(double currentPrice, double referencePrice) {
    double priceDifference = currentPrice - referencePrice;
    double points = priceDifference / _Point;
    return points;
}

// drawings
void drawObject(){
   // high
   ObjectDelete(NULL, "highPrice");
   ObjectCreate(NULL, "highPrice", OBJ_TREND, 0, timeStart, highPrice, timeEnd, highPrice);
   ObjectSetInteger(NULL, "highPrice", OBJPROP_WIDTH, 2);
   ObjectSetInteger(NULL, "highPrice", OBJPROP_COLOR,clrBlue);
   
    // low
   ObjectDelete(NULL, "lowPrice");
   ObjectCreate(NULL, "lowPrice", OBJ_TREND, 0, timeStart, lowPrice, timeEnd, lowPrice);
   ObjectSetInteger(NULL, "lowPrice", OBJPROP_WIDTH, 2);
   ObjectSetInteger(NULL, "lowPrice", OBJPROP_COLOR,clrBlue);
   

}


// find range 
void findRange(){
  int timeRangeStartIdx = iBarShift(_Symbol,PERIOD_CURRENT,timeStart);
      
  int timeRangeEndIdx = iBarShift(_Symbol,PERIOD_CURRENT,timeEnd);
       
  int highIdx = iHighest(_Symbol,PERIOD_CURRENT,MODE_HIGH,timeRangeStartIdx,timeRangeEndIdx);
       
  int lowIdx = iLowest(_Symbol,PERIOD_CURRENT,MODE_LOW,timeRangeStartIdx,timeRangeEndIdx);
       
  highPrice = iHigh(_Symbol,PERIOD_CURRENT,highIdx);
       
  lowPrice = iLow(_Symbol,PERIOD_CURRENT,lowIdx);
            
  drawObject();
}

// end of day
void endOfDayActions(){
  ObjectDelete(NULL, "highPrice");
  ObjectDelete(NULL, "lowPrice");
  buyCntToday = 0;
  sellCntToday = 0;
  lowPrice = 0;
  highPrice = 500;
  highTaken = false;
  lowTaken = false;
  
  bool closeTrades = InpCloseTrades;    
  if(closeTrades) {
      for(int i = PositionsTotal()-1; i >= 0; i--){
         ulong posTicket = PositionGetTicket(i);
         if(PositionSelectByTicket(posTicket)){
            Print("Position ticket:",posTicket);
            if(trade.PositionClose(posTicket)){
               Print("Pos ticket:", posTicket, " Was closed, Reason: End Of Day");
            }
         }
      }
  }   
}




// cycle
void cycle(){

     datetime cycleDate[] = {
     
                         D'2009.11.24', D'2009.12.06' };
              
   
   //todays date
    datetime today = TimeCurrent();
    
    
    //check if pivot has occured
   if(today >= nextPivot){
      
      pivotFound = false;
   }
   
   // find the current pivot and the pivot after that
   while (pivotFound == false) {
   
    // current point in the cycle sheet
    datetime currentDate = cycleDate[icycle];   
    
    // if today is larger than the point in the cycle sheet set the currentpivot to this date
      if(currentDate <= today) {
         
         currentPivot = currentDate;
         
         waitingForHigh = !waitingForHigh;
         
         icycle++;
         
         // if today is smaller than the point in the cycle sheet, set the nextpivot to this date and break the loop
      } else{ 
         nextPivot = currentDate; 
         pivotFound = true;
         
         }
      
       Print("Current point in sheet:",currentPivot, " Today: ",today, " next pivot:", nextPivot, " waiting for high:",waitingForHigh);
   }
  
}


//martingale
void martingale(){
 
 int cntLosses = 0;
if (HistorySelect(0, INT_MAX)) {
    for (int i = HistoryDealsTotal() - 1; i >= 0; i--) {
        const ulong Ticket = HistoryDealGetTicket(i);

        if ((HistoryDealGetInteger(Ticket, DEAL_MAGIC) == InpMagicNumber) && (HistoryDealGetString(Ticket, DEAL_SYMBOL) == Symbol())) {
            if (HistoryDealGetDouble(Ticket, DEAL_PROFIT) < (-10)) {
                cntLosses++;}
             if(HistoryDealGetDouble(Ticket, DEAL_PROFIT) > 0) {
                break; // Exit the loop if a profitable trade is encountered
            }
        }
    }
} 
if(cntLosses >= InpMartingaleThreshold){ 
   martingaleMultiplier = cntLosses;
   martinGale = true; } 
   else{ martinGale = false;}
Print("number of losses before a profit: ",cntLosses, " martingale time is ", martinGale, " the multiplier is ", martingaleMultiplier);
   
}


   
// update stop loss

void updateStopLoss(){

            for(int i = PositionsTotal()-1; i>=0; i--){
               ulong posTicket = PositionGetTicket(i);
               if(PositionSelectByTicket(posTicket)){
                  double posSL = PositionGetDouble(POSITION_SL);
                  double posTP = PositionGetDouble(POSITION_TP);
                  
                  if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){
                     int shift = iLowest(_Symbol,PERIOD_CURRENT,MODE_LOW,InpSLBars,1);
                     double slLow = iLow(_Symbol,PERIOD_CURRENT,shift);
                     slLow = NormalizeDouble(slLow,_Digits);
                     if(slLow > posSL){
                        if(trade.PositionModify(posTicket,slLow,posTP)){
                           Print("POS:",posTicket, " stop loss was modified + posTP: ", posTP);
                        }
                     }
                     
                     
                  }else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL){
                    int shift = iHighest(_Symbol,PERIOD_CURRENT,MODE_HIGH,InpSLBars,1);
                     double slHigh = iHigh(_Symbol,PERIOD_CURRENT,shift);
                     slHigh = NormalizeDouble(slHigh,_Digits);
                     if(slHigh < posSL || posSL == 0){
                        if(trade.PositionModify(posTicket,slHigh,posTP)){
                           Print("POS:",posTicket, " stop loss was modified");
                        }
                     }
                     
                     
                  }
               }
               
            } 
}
