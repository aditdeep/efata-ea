//+------------------------------------------------------------------+
//|                                                        efata.mq5  |
//|                                          (c)Efata v1.0            |
//|  Manual-trigger (pending order) + auto MACD/Ichimoku management  |
//|  martingale + accumulated profit exit                            |
//|  isIndi=1 -> MACD(5,13,1) ; isIndi=2 -> Ichimoku(5,13,26)        |
//+------------------------------------------------------------------+
#property copyright "(c)Efata v1.0"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//==================== KONSTANTA ====================
#define MAGIC_KENDALI    900000
#define HARGA_KENDALI    900000.0
#define VOLUME_KENDALI   1.0
#define HARGA_BUY_STOP   777777.0
#define HARGA_SELL_STOP  0.07
#define MACD_FAST        5
#define MACD_SLOW        13
#define MACD_SIGNAL      1
#define LOOKBACK_PV      50
#define MAX_MAGIC_TRACK  50
#define MAGIC_LOOP       88888
#define MAGIC_PARAM      55555
#define HARGA_LOOP       800000.0
#define MIN_BAR_GAP      5
#define MAX_LEVEL        0

#include "indi.h"

//==================== INPUT PARAMETERS ====================
input int    InpIsIndi            = 1;
input double InpExitPct           = 0;
input double InpXLot              = 2.3;
input double InpExitUSD           = 0;
input double InpExitBid           = 0;
input double InpExitBidMin        = 0;
input int    InpAddTemen          = 1;
input int    InpAllowPeakNegatif  = 1;
input double InpBT                = 0;
input int    InpLoopPerDay        = 0;
input int    InpStartTrade        = 0;
input int    InpEndTrade          = 24;
input int    InpWIBOffset         = 7;
input int    InpIchiShiftX        = 100;
input int    InpIchiBuffer        = 150;
input double InpMMRatio           = 1000000;
input bool   InpSplitLot          = true;
input int    InpTR                = 1;
input int    InpDetekPuncak       = 0;

//==================== GLOBAL VARIABLES ====================
CTrade   trade;
int      gMacdHandles[8];
int      gFractalHandles[8];
int      gIchiHandles[8];

int      gMagicCount      = 0;
datetime gLastMacdCheck   = 0;
int      gIsIndi          = 1;
double   gExitPct         = 0;
double   gXLot            = 2.3;
double   gExitUSD         = 0;
double   gExitBid         = 0;
double   gExitBidMin      = 0;
int      gAddTemen        = 1;
int      gAllowPeakNegatif= 1;
int      gLoopPerDay      = 0;
int      gStartTrade      = 0;
int      gEndTrade        = 24;
int      gWIBOffset       = 7;

double   gMMRatio         = 1000000.0;
bool     gSplitLot        = true;

int      gTR              = 1;
int      gDetekPuncak     = 0;
int      gLoopCountToday  = 0;
datetime gLoopDay         = 0;

ulong    gTriggered[];
int      gTriggeredCount = 0;

//==================== STRUCT MagicState ====================
struct MagicState
{
   long     magic;
   int      zTF, eTF, xTF;
   double   initLot;
   double   xlot;
   datetime lastBarE;
   int      lastPeakIdx;
   int      lastValleyIdx;
   datetime lastPeakTime;
   datetime lastValleyTime;
};
MagicState gMagics[MAX_MAGIC_TRACK];

datetime gLastPeakTimePerE[8];
datetime gLastValleyTimePerE[8];
int      gLastPeakIdxPerE[8];
int      gLastValleyIdxPerE[8];
double   gLastPeakPricePerE[8];
double   gLastValleyPricePerE[8];

//==================== STRUCT ScanResult ====================
struct ScanResult
{
   ulong    buyT[];   double buyL[];  double buyP[];  string buyC[];
   ulong    sellT[];  double sellL[]; double sellP[]; string sellC[];
   ulong    bsT[];    double bsL[];   double bsP[];   string bsC[];
   ulong    ssT[];    double ssL[];   double ssP[];   string ssC[];
   int      nBuy, nSell, nBS, nSS;

   void Scan(long magic)
   {
      nBuy=nSell=nBS=nSS=0;
      ArrayResize(buyT,0);  ArrayResize(buyL,0);  ArrayResize(buyP,0);  ArrayResize(buyC,0);
      ArrayResize(sellT,0); ArrayResize(sellL,0); ArrayResize(sellP,0); ArrayResize(sellC,0);
      ArrayResize(bsT,0);   ArrayResize(bsL,0);   ArrayResize(bsP,0);   ArrayResize(bsC,0);
      ArrayResize(ssT,0);   ArrayResize(ssL,0);   ArrayResize(ssP,0);   ArrayResize(ssC,0);

      int pt = PositionsTotal();
      for(int i=0;i<pt;i++)
      {
         ulong tk = PositionGetTicket(i);
         if(tk==0) continue;
         if(!PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         if((long)PositionGetInteger(POSITION_MAGIC)!=magic) continue;
         long   type = PositionGetInteger(POSITION_TYPE);
         double lot  = PositionGetDouble(POSITION_VOLUME);
         double prc  = PositionGetDouble(POSITION_PRICE_OPEN);
         string cmt  = PositionGetString(POSITION_COMMENT);
         if(type==POSITION_TYPE_BUY)
         {
            int n=nBuy++;
            ArrayResize(buyT,nBuy);ArrayResize(buyL,nBuy);ArrayResize(buyP,nBuy);ArrayResize(buyC,nBuy);
            buyT[n]=tk; buyL[n]=lot; buyP[n]=prc; buyC[n]=cmt;
         }
         else if(type==POSITION_TYPE_SELL)
         {
            int n=nSell++;
            ArrayResize(sellT,nSell);ArrayResize(sellL,nSell);ArrayResize(sellP,nSell);ArrayResize(sellC,nSell);
            sellT[n]=tk; sellL[n]=lot; sellP[n]=prc; sellC[n]=cmt;
         }
      }

      int ot = OrdersTotal();
      for(int i=0;i<ot;i++)
      {
         ulong tk = OrderGetTicket(i);
         if(tk==0) continue;
         if(!OrderSelect(tk)) continue;
         if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
         if((long)OrderGetInteger(ORDER_MAGIC)!=magic) continue;
         long   type = OrderGetInteger(ORDER_TYPE);
         double lot  = OrderGetDouble(ORDER_VOLUME_CURRENT);
         double prc  = OrderGetDouble(ORDER_PRICE_OPEN);
         string cmt  = OrderGetString(ORDER_COMMENT);
         if(type==ORDER_TYPE_BUY_STOP)
         {
            int n=nBS++;
            ArrayResize(bsT,nBS);ArrayResize(bsL,nBS);ArrayResize(bsP,nBS);ArrayResize(bsC,nBS);
            bsT[n]=tk; bsL[n]=lot; bsP[n]=prc; bsC[n]=cmt;
         }
         else if(type==ORDER_TYPE_SELL_STOP)
         {
            int n=nSS++;
            ArrayResize(ssT,nSS);ArrayResize(ssL,nSS);ArrayResize(ssP,nSS);ArrayResize(ssC,nSS);
            ssT[n]=tk; ssL[n]=lot; ssP[n]=prc; ssC[n]=cmt;
         }
      }
   }
};

ENUM_TIMEFRAMES MapTF(int d)
{
   switch(d)
   {
      case 1: return PERIOD_M1;
      case 2: return PERIOD_M5;
      case 3: return PERIOD_M30;
      case 4: return PERIOD_H4;
      case 5: return PERIOD_D1;
      case 6: return PERIOD_W1;
      case 7: return PERIOD_MN1;
   }
   return PERIOD_M1;
}

//==================== FORWARD DECLARATIONS ====================
void ProcessNewOrderCommand(double tp, double sl);
void CloseAllExceptKendali();
void CloseMagic(long magic);

//+------------------------------------------------------------------+
//| Helpers: Norm
//+------------------------------------------------------------------+
double NormLot(double lot)
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step<=0) step=0.01;
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathFloor(lot/step)*step;
   if(lot<mn) lot=mn;
   if(lot>mx) lot=mx;
   return NormalizeDouble(lot,2);
}

double NormPrice(double price)
{
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(ts<=0) ts = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(ts<=0) ts = _Point;
   return NormalizeDouble(MathRound(price/ts)*ts, _Digits);
}

double MMLot()
{
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double ratio = (gMMRatio > 0) ? gMMRatio : 1000000.0;
   return NormLot(bal / ratio);
}

//+------------------------------------------------------------------+
//| Magic management
//+------------------------------------------------------------------+
int FindMagic(long magic)
{
   for(int i=0;i<gMagicCount;i++)
      if(gMagics[i].magic==magic) return i;
   return -1;
}

int FindOrAddMagic(long magic)
{
   int idx = FindMagic(magic);
   if(idx>=0) return idx;
   if(gMagicCount>=MAX_MAGIC_TRACK) return -1;
   idx = gMagicCount++;
   gMagics[idx].magic = magic;
   return idx;
}

void RegisterMagic(long magic, double lot, double xlot)
{
   int idx = FindOrAddMagic(magic);
   if(idx<0) return;
   int zTF = (int)((magic/100)%10);
   int eTF = (int)((magic/10)%10);
   int xTF = (int)(magic%10);
   if(xTF==0) xTF=eTF;
   gMagics[idx].magic         = magic;
   gMagics[idx].zTF           = zTF;
   gMagics[idx].eTF           = eTF;
   gMagics[idx].xTF           = xTF;
   gMagics[idx].initLot       = lot;
   gMagics[idx].xlot          = xlot;
   gMagics[idx].lastBarE      = 0;
   gMagics[idx].lastPeakIdx   = -1;
   gMagics[idx].lastValleyIdx = -1;
   gMagics[idx].lastPeakTime   = 0;
   gMagics[idx].lastValleyTime = 0;
}

bool ParseKendaliTP(double tp, int &zTF, int &eTF, int &xTF, long &magic, double &lot)
{
   zTF=eTF=xTF=0; magic=0; lot=0;
   if(tp<=0) return false;

   long ip = (long)MathFloor(tp);
   double frac = NormalizeDouble(tp - (double)ip, 2);
   int digits = (ip<=0)?1:(int)MathFloor(MathLog10((double)ip))+1;

   if(digits==3)
   {
      int E  = (int)(ip/100);
      int LL = (int)(ip%100);
      if(E<1 || E>7) return false;
      zTF=E; eTF=E; xTF=0;
      magic = (long)E*100 + (long)E*10 + 0;
      lot = (double)LL + frac;
      if(lot == 0) lot = MMLot();
      return true;
   }
   else if(digits==4 && (ip/1000)!=8)
   {
      int Z  = (int)(ip/1000);
      int E  = (int)((ip/100)%10);
      int X  = (int)((ip/10)%10);
      int lotInt = (int)(ip%10);
      zTF=Z; eTF=E; xTF=X;
      magic = (long)Z*100 + (long)E*10 + (long)X;
      lot = (double)lotInt + frac;
      return true;
   }
   else if(digits==5)
   {
      int Z  = (int)(ip/10000);
      int E  = (int)((ip/1000)%10);
      int X  = (int)((ip/100)%10);
      int lotInt = (int)(ip%100);
      zTF=Z; eTF=E; xTF=X;
      magic = (long)Z*100 + (long)E*10 + (long)X;
      lot = (double)lotInt + frac;
      return true;
   }
   return false;
}

int CountColons(string s)
{
   int c=0;
   for(int i=0;i<StringLen(s);i++)
      if(StringGetCharacter(s,i)==':') c++;
   return c;
}

int GetLevelFromComment(string cmt)
{
   int p = StringFind(cmt,"-L");
   if(p<0) return -1;
   p += 2;
   string num="";
   while(p<StringLen(cmt))
   {
      ushort ch = StringGetCharacter(cmt,p);
      if(ch>='0' && ch<='9'){ num+=ShortToString(ch); p++; }
      else break;
   }
   if(StringLen(num)==0) return -1;
   return (int)StringToInteger(num);
}

int GetTFromComment(string cmt)
{
   int p = StringFind(cmt,"-T");
   if(p<0) return -1;
   p += 2;
   string num="";
   while(p<StringLen(cmt))
   {
      ushort ch = StringGetCharacter(cmt,p);
      if(ch>='0' && ch<='9'){ num+=ShortToString(ch); p++; }
      else break;
   }
   if(StringLen(num)==0) return 0;
   return (int)StringToInteger(num);
}

//+------------------------------------------------------------------+
//| Order creation helpers
//+------------------------------------------------------------------+
bool CreateBuyStop(double price, double lot, long magic, string cmt)
{
   trade.SetExpertMagicNumber(magic);
   double p = NormPrice(price);
   double v = NormLot(lot);
   bool ok = trade.BuyStop(v, p, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, cmt);
   if(!ok) PrintFormat("BuyStop FAIL magic=%d retcode=%d", magic, trade.ResultRetcode());
   return ok;
}

bool CreateSellStop(double price, double lot, long magic, string cmt)
{
   trade.SetExpertMagicNumber(magic);
   double p = NormPrice(price);
   double v = NormLot(lot);
   bool ok = trade.SellStop(v, p, _Symbol, 0.0, 0.0, ORDER_TIME_GTC, 0, cmt);
   if(!ok) PrintFormat("SellStop FAIL magic=%d retcode=%d", magic, trade.ResultRetcode());
   return ok;
}

double MaxBrokerLot()
{
   double mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(mx <= 0) mx = 100.0;
   return mx;
}

bool CreateBuyStopSplit(double price, double lot, long magic, string cmt)
{
   if(!gSplitLot || lot <= MaxBrokerLot())
      return CreateBuyStop(price, lot, magic, cmt);
   double mx = MaxBrokerLot();
   double rem = lot;
   bool ok = true;
   int part = 1;
   while(rem > 0)
   {
      double chunk = (rem > mx) ? mx : rem;
      string cmtPart = cmt + (part>1 ? ("-p"+IntegerToString(part)) : "");
      if(!CreateBuyStop(price, chunk, magic, cmtPart)) ok = false;
      rem = NormLot(rem - chunk);
      part++;
      if(rem > 0) Sleep(100);
   }
   return ok;
}

bool CreateSellStopSplit(double price, double lot, long magic, string cmt)
{
   if(!gSplitLot || lot <= MaxBrokerLot())
      return CreateSellStop(price, lot, magic, cmt);
   double mx = MaxBrokerLot();
   double rem = lot;
   bool ok = true;
   int part = 1;
   while(rem > 0)
   {
      double chunk = (rem > mx) ? mx : rem;
      string cmtPart = cmt + (part>1 ? ("-p"+IntegerToString(part)) : "");
      if(!CreateSellStop(price, chunk, magic, cmtPart)) ok = false;
      rem = NormLot(rem - chunk);
      part++;
      if(rem > 0) Sleep(100);
   }
   return ok;
}

bool CreateBuyMarketSplit(double lot, long magic, string cmt)
{
   double mx = MaxBrokerLot();
   if(!gSplitLot || lot <= mx)
   {
      trade.SetExpertMagicNumber(magic);
      bool ok = trade.Buy(NormLot(lot), _Symbol, 0.0, 0.0, 0.0, cmt);
      if(!ok) PrintFormat("BuyMarket FAIL magic=%d retcode=%d", magic, trade.ResultRetcode());
      return ok;
   }
   double rem = lot;
   bool ok = true;
   int part = 1;
   while(rem > 0)
   {
      double chunk = (rem > mx) ? mx : rem;
      string cmtPart = cmt + (part>1 ? ("-p"+IntegerToString(part)) : "");
      trade.SetExpertMagicNumber(magic);
      if(!trade.Buy(NormLot(chunk), _Symbol, 0.0, 0.0, 0.0, cmtPart))
      { PrintFormat("BuyMarket FAIL part=%d magic=%d retcode=%d", part, magic, trade.ResultRetcode()); ok=false; }
      rem = NormLot(rem - chunk);
      part++;
      if(rem > 0) Sleep(100);
   }
   return ok;
}

bool CreateSellMarketSplit(double lot, long magic, string cmt)
{
   double mx = MaxBrokerLot();
   if(!gSplitLot || lot <= mx)
   {
      trade.SetExpertMagicNumber(magic);
      bool ok = trade.Sell(NormLot(lot), _Symbol, 0.0, 0.0, 0.0, cmt);
      if(!ok) PrintFormat("SellMarket FAIL magic=%d retcode=%d", magic, trade.ResultRetcode());
      return ok;
   }
   double rem = lot;
   bool ok = true;
   int part = 1;
   while(rem > 0)
   {
      double chunk = (rem > mx) ? mx : rem;
      string cmtPart = cmt + (part>1 ? ("-p"+IntegerToString(part)) : "");
      trade.SetExpertMagicNumber(magic);
      if(!trade.Sell(NormLot(chunk), _Symbol, 0.0, 0.0, 0.0, cmtPart))
      { PrintFormat("SellMarket FAIL part=%d magic=%d retcode=%d", part, magic, trade.ResultRetcode()); ok=false; }
      rem = NormLot(rem - chunk);
      part++;
      if(rem > 0) Sleep(100);
   }
   return ok;
}

datetime ToWIB(datetime brokerTime)
{
   return brokerTime + (datetime)(gWIBOffset * 3600);
}

bool IsWithinTradingHours()
{
   datetime wibTime = ToWIB(TimeCurrent());
   MqlDateTime dt;
   TimeToStruct(wibTime, dt);
   int hourWIB = dt.hour;
   
   if(gStartTrade < gEndTrade)
      return (hourWIB >= gStartTrade && hourWIB < gEndTrade);
   else
      return (hourWIB >= gStartTrade || hourWIB < gEndTrade);
}

bool FindKendali(ulong &ticket, double &tp, double &sl)
{
   ticket=0; tp=0; sl=0;
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=MAGIC_KENDALI) continue;
      if(OrderGetInteger(ORDER_TYPE)!=ORDER_TYPE_SELL_LIMIT) continue;
      ticket = tk;
      tp = OrderGetDouble(ORDER_TP);
      sl = OrderGetDouble(ORDER_SL);
      return true;
   }
   return false;
}

void EnsureLimitKendali()
{
   ulong tk; double tp,sl;
   if(FindKendali(tk,tp,sl)) return;
   trade.SetExpertMagicNumber(MAGIC_KENDALI);
   double price = NormPrice(HARGA_KENDALI);
   bool ok = trade.SellLimit(VOLUME_KENDALI, price, _Symbol, 0.0, 0.0,
                             ORDER_TIME_GTC, 0, "(c)Efata v1.0");
   if(!ok) PrintFormat("EnsureLimitKendali FAIL retcode=%d", trade.ResultRetcode());
}

bool GetLimitKendali(ulong &ticket, double &tp, double &sl)
{
   return FindKendali(ticket,tp,sl);
}

void ResetKendaliTP(ulong ticket)
{
   if(!OrderSelect(ticket)) return;
   double price = OrderGetDouble(ORDER_PRICE_OPEN);
   double sl    = OrderGetDouble(ORDER_SL);
   trade.SetExpertMagicNumber(MAGIC_KENDALI);
   trade.OrderModify(ticket, price, sl, 0.0, ORDER_TIME_GTC, 0);
}

bool HasPositionForMagic(long magic)
{
   int pt = PositionsTotal();
   for(int i=0;i<pt;i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk==0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)==magic) return true;
   }
   return false;
}

bool HasPendingForMagic(long magic)
{
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)==magic) return true;
   }
   return false;
}

bool FindLoopLS(ulong &ticket, double &tp)
{
   ticket=0; tp=0;
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=MAGIC_LOOP) continue;
      if(OrderGetInteger(ORDER_TYPE)!=ORDER_TYPE_SELL_LIMIT) continue;
      ticket = tk;
      tp = OrderGetDouble(ORDER_TP);
      return true;
   }
   return false;
}

bool FindLoopLSForTP(double newTP)
{
   int nz,ne,nx; long nmagic; double nlot;
   if(!ParseKendaliTP(newTP,nz,ne,nx,nmagic,nlot)) return false;
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=MAGIC_LOOP) continue;
      if(OrderGetInteger(ORDER_TYPE)!=ORDER_TYPE_SELL_LIMIT) continue;
      double curTP = OrderGetDouble(ORDER_TP);
      int cz,ce,cx; long cmagic; double clot;
      if(ParseKendaliTP(curTP,cz,ce,cx,cmagic,clot) && cmagic==nmagic)
         return true;
   }
   return false;
}

void CreateLoopLSWithTP(double tp)
{
   if(FindLoopLSForTP(tp))
   {
      PrintFormat("CreateLoopLS: loop LS untuk magic ini sudah ada, skip");
      return;
   }
   trade.SetExpertMagicNumber(MAGIC_LOOP);
   double p = NormPrice(HARGA_LOOP);
   bool ok = trade.SellLimit(VOLUME_KENDALI, p, _Symbol, 0.0, tp,
                             ORDER_TIME_GTC, 0, "LOOP");
   if(!ok) PrintFormat("CreateLoopLS FAIL retcode=%d", trade.ResultRetcode());
}

void CheckLoopLS()
{
   ulong tks[]; double tps_arr[]; int cnt=0;
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=MAGIC_LOOP) continue;
      if(OrderGetInteger(ORDER_TYPE)!=ORDER_TYPE_SELL_LIMIT) continue;
      double tp = OrderGetDouble(ORDER_TP);
      if(tp==0) continue;
      ArrayResize(tks, cnt+1); ArrayResize(tps_arr, cnt+1);
      tks[cnt]=tk; tps_arr[cnt]=tp; cnt++;
   }
   if(cnt==0) return;

   datetime now    = TimeCurrent();
   datetime nowWIB = ToWIB(now);
   datetime today  = nowWIB - (nowWIB % 86400);
   if(today != gLoopDay)
   {
      gLoopDay        = today;
      gLoopCountToday = 0;
   }

   for(int i=0;i<cnt;i++)
   {
      if(gLoopPerDay>0 && gLoopCountToday>=gLoopPerDay) break;
      double tp = tps_arr[i];
      int z,e,x; long magic; double lot;
      if(!ParseKendaliTP(tp,z,e,x,magic,lot)) continue;
      if(HasPositionForMagic(magic) || HasPendingForMagic(magic)) continue;

      if(gIsIndi==2)
      {
         bool isNew = (FindMagic(magic)<0);
         ProcessNewOrderCommand(tp, 0.0);
         if(isNew) gLoopCountToday++;
      }
      else
      {
         ProcessNewOrderCommand(tp, 0.0);
         gLoopCountToday++;
      }
   }
}

bool FindParamLSByPrice(double targetPrice, ulong &ticket)
{
   ticket=0;
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=MAGIC_PARAM) continue;
      if(OrderGetInteger(ORDER_TYPE)!=ORDER_TYPE_SELL_LIMIT) continue;
      double prc = OrderGetDouble(ORDER_PRICE_OPEN);
      if((long)MathRound(prc)==(long)MathRound(targetPrice))
      {
         ticket=tk;
         return true;
      }
   }
   return false;
}

void CreateParamLS()
{
   double prices[16] = {100001,100002,100003,100004,100005,100006,100007,100008,100009,100010,100011,100012,100013,100014,100015,100016};
   double tps[16];
   tps[0]=(double)gIsIndi;
   tps[1]=gExitPct;
   tps[2]=gExitUSD;
   tps[3]=gExitBid;
   tps[4]=gExitBidMin;
   tps[5]=gXLot;
   tps[6]=(double)gAddTemen;
   tps[7]=(double)gAllowPeakNegatif;
   tps[8]=(double)gLoopPerDay;
   tps[9]=(double)gStartTrade;
   tps[10]=(double)gEndTrade;
   tps[11]=(double)gWIBOffset;
   tps[12]=(double)gIchiShiftX;
   tps[13]=(double)gIchiBuffer;
   tps[14]=(double)gTR;
   tps[15]=(double)gDetekPuncak;
   string names[16] = {"isIndi","exitPct","exitUSD","exitBid","exitBidMin","xLot","addTemen","allowPeakNeg","loopPerDay","startTrade","endTrade","wibOffset","ichiShiftX","ichiBuffer","TR","detekPuncak"};

   for(int i=0;i<16;i++)
   {
      ulong tk;
      if(FindParamLSByPrice(prices[i],tk)) continue;
      trade.SetExpertMagicNumber(MAGIC_PARAM);
      double p = NormPrice(prices[i]);
      bool ok = trade.SellLimit(VOLUME_KENDALI, p, _Symbol, 0.0, tps[i],
                                ORDER_TIME_GTC, 0, names[i]);
      if(!ok) PrintFormat("CreateParamLS %s FAIL retcode=%d", names[i], trade.ResultRetcode());
   }
}

void DeleteAllParamLS()
{
   ulong tickets[]; int cnt=0;
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=MAGIC_PARAM) continue;
      ArrayResize(tickets,cnt+1);
      tickets[cnt++]=tk;
   }
   for(int i=0;i<cnt;i++)
   {
      trade.OrderDelete(tickets[i]);
      Sleep(150);
   }
}

void SyncParamsFromMagicParam()
{
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=MAGIC_PARAM) continue;
      if(OrderGetInteger(ORDER_TYPE)!=ORDER_TYPE_SELL_LIMIT) continue;
      int prc = (int)MathRound(OrderGetDouble(ORDER_PRICE_OPEN));
      double tp = OrderGetDouble(ORDER_TP);
      switch(prc)
      {
         case 100001: gIsIndi          = (int)MathRound(tp); break;
         case 100002: gExitPct         = tp;                 break;
         case 100003: gExitUSD         = tp;                 break;
         case 100004: gExitBid         = tp;                 break;
         case 100005: gExitBidMin      = tp;                 break;
         case 100006:
            gXLot = tp;
            for(int j=0;j<gMagicCount;j++) gMagics[j].xlot = gXLot;
            break;
         case 100007: gAddTemen        = (int)MathRound(tp); break;
         case 100008: gAllowPeakNegatif= (int)MathRound(tp); break;
         case 100009: gLoopPerDay      = (int)MathRound(tp); break;
         case 100010: gStartTrade      = (int)MathRound(tp); break;
         case 100011: gEndTrade        = (int)MathRound(tp); break;
         case 100012: gWIBOffset       = (int)MathRound(tp); break;
         case 100013: gIchiShiftX      = (int)MathRound(tp); break;
         case 100014: gIchiBuffer      = (int)MathRound(tp); break;
         case 100015: gTR             = (int)MathRound(tp); break;
         case 100016: gDetekPuncak    = (int)MathRound(tp); break;
      }
   }
}

void DeletePendingsExcept(const long &keepMagics[], int keepCount)
{
   ulong tickets[]; int cnt=0;
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      long mg = (long)OrderGetInteger(ORDER_MAGIC);
      bool keep=false;
      for(int k=0;k<keepCount;k++) if(mg==keepMagics[k]){ keep=true; break; }
      if(keep) continue;
      ArrayResize(tickets,cnt+1);
      tickets[cnt++]=tk;
   }
   for(int i=0;i<cnt;i++)
   {
      trade.OrderDelete(tickets[i]);
      Sleep(200);
   }
}

void ClosePositionsCloseByThenSingle(long onlyMagic)
{
   bool paired=true;
   while(paired)
   {
      paired=false;
      ulong buyTk=0, sellTk=0;
      int pt = PositionsTotal();
      for(int i=0;i<pt;i++)
      {
         ulong tk = PositionGetTicket(i);
         if(tk==0) continue;
         if(!PositionSelectByTicket(tk)) continue;
         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
         long mg = (long)PositionGetInteger(POSITION_MAGIC);
         if(onlyMagic>=0 && mg!=onlyMagic) continue;
         long type = PositionGetInteger(POSITION_TYPE);
         if(type==POSITION_TYPE_BUY  && buyTk==0)  buyTk=tk;
         if(type==POSITION_TYPE_SELL && sellTk==0) sellTk=tk;
         if(buyTk!=0 && sellTk!=0) break;
      }
      if(buyTk!=0 && sellTk!=0)
      {
         if(trade.PositionCloseBy(buyTk,sellTk))
            paired=true;
         else
            break;
         Sleep(200);
      }
   }
   ulong tickets[]; int cnt=0;
   int pt = PositionsTotal();
   for(int i=0;i<pt;i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk==0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long mg = (long)PositionGetInteger(POSITION_MAGIC);
      if(onlyMagic>=0 && mg!=onlyMagic) continue;
      ArrayResize(tickets,cnt+1);
      tickets[cnt++]=tk;
   }
   for(int i=0;i<cnt;i++)
   {
      trade.PositionClose(tickets[i]);
      Sleep(200);
   }
}

void CloseMagic(long magic)
{
   ulong tickets[]; int cnt=0;
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)!=magic) continue;
      ArrayResize(tickets,cnt+1);
      tickets[cnt++]=tk;
   }
   for(int i=0;i<cnt;i++){ trade.OrderDelete(tickets[i]); Sleep(200); }
   ClosePositionsCloseByThenSingle(magic);

   int midx = FindMagic(magic);
   if(midx >= 0)
   {
      bool hasLoop = false;
      int ot2 = OrdersTotal();
      for(int lo=0;lo<ot2;lo++)
      {
         ulong ltk = OrderGetTicket(lo);
         if(ltk==0) continue;
         if(!OrderSelect(ltk)) continue;
         if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
         if((long)OrderGetInteger(ORDER_MAGIC)!=MAGIC_LOOP) continue;
         if(OrderGetInteger(ORDER_TYPE)!=ORDER_TYPE_SELL_LIMIT) continue;
         double ltp = OrderGetDouble(ORDER_TP);
         int lz,le,lx; long lmag; double llot;
         if(ParseKendaliTP(ltp,lz,le,lx,lmag,llot) && lmag==magic)
         { hasLoop=true; break; }
      }
      if(hasLoop) gMagics[midx].initLot = 0;
   }
}

void CloseAllExceptKendali()
{
   long keep[1]; keep[0]=MAGIC_KENDALI;
   DeletePendingsExcept(keep,1);
   ClosePositionsCloseByThenSingle(-1);
}

void Handle_TP19()
{
   long keep[3]; keep[0]=MAGIC_KENDALI; keep[1]=MAGIC_LOOP; keep[2]=MAGIC_PARAM;
   DeletePendingsExcept(keep,3);
   ClosePositionsCloseByThenSingle(-1);
}

void Handle_TP20()
{
   long keep[1]; keep[0]=MAGIC_KENDALI;
   DeletePendingsExcept(keep,1);
   ClosePositionsCloseByThenSingle(-1);
}

void ProcessNewOrderCommand(double tp, double sl)
{
   if(!IsWithinTradingHours())
   {
      PrintFormat("ProcessNewOrder: Di luar jam trading (%d:00 - %d:00 WIB), skip", gStartTrade, gEndTrade);
      return;
   }

   int z,e,x; long magic; double lot;
   if(!ParseKendaliTP(tp,z,e,x,magic,lot)) return;

   if(lot==0) lot = MMLot();
   else       lot = NormLot(lot);

   double useXlot = (sl>0)? sl : gXLot;
   RegisterMagic(magic, lot, useXlot);

   int idx = FindMagic(magic);
   if(idx<0) return;

   if(gIsIndi==2)
   {
      PrintFormat("ProcessNewOrder ICHI: magic %d registered, L0 menunggu sinyal Ichimoku", magic);
      return;
   }

   if(gIsIndi==1 && gMagics[idx].zTF==gMagics[idx].eTF)
   {
      bool hasPos = HasPositionForMagic(magic);
      bool hasOrd = HasPendingForMagic(magic);
      if(!hasPos && !hasOrd)
      {
         string cmt = IntegerToString(magic)+":MCD-L0 ";
         CreateBuyStopSplit(HARGA_BUY_STOP, lot, magic, cmt);
         CreateSellStopSplit(HARGA_SELL_STOP, lot, magic, cmt);
      }
      else
      {
         PrintFormat("ProcessNewOrder: magic %d already has pos/ord, skip", magic);
      }
   }
   else if(gIsIndi==1 && gMagics[idx].zTF > gMagics[idx].eTF)
   {
      bool hasPos = HasPositionForMagic(magic);
      bool hasOrd = HasPendingForMagic(magic);
      if(!hasPos && !hasOrd)
      {
         double zbuf[];
         if(GetMacdBuffer(gMagics[idx].zTF, zbuf, 3) && ArraySize(zbuf)>=2)
         {
            string cmt = IntegerToString(magic)+":MCD-L0 ";
            if(zbuf[1] >= 0.0)
               CreateBuyStopSplit(HARGA_BUY_STOP, lot, magic, cmt);
            else
               CreateSellStopSplit(HARGA_SELL_STOP, lot, magic, cmt);
         }
      }
      else
      {
         PrintFormat("ProcessNewOrder Z>E: magic %d already has pos/ord, skip", magic);
      }
   }
}

void CheckBTAutoOrder()
{
   if(InpBT<=0) return;
   if(!MQLInfoInteger(MQL_TESTER)) return;

   long ip = (long)MathFloor(InpBT);
   double frac = NormalizeDouble(InpBT - (double)ip, 2);
   int digits = (ip<=0)?1:(int)MathFloor(MathLog10((double)ip))+1;

   if(digits==4 && ip>=8100 && ip<=8799)
   {
      int ELL = (int)(ip-8000);
      int E  = ELL/100;
      int LL = ELL%100;
      double loopTP = (double)E*11000.0 + (double)LL + frac;
      if(!FindLoopLSForTP(loopTP)) CreateLoopLSWithTP(loopTP);
      return;
   }

   long btInt = ip;
   if(!(btInt>0 && btInt<77799)) return;
   int z,e,x; long magic; double lot;
   if(!ParseKendaliTP(InpBT,z,e,x,magic,lot)) return;
   if(HasPositionForMagic(magic) || HasPendingForMagic(magic)) return;
   if(lot==0) lot = MMLot(); else lot = NormLot(lot);
   if(gIsIndi==2)
   {
      if(FindMagic(magic)<0)
         RegisterMagic(magic, lot, gXLot);
      return;
   }
   string cmt = IntegerToString(magic)+":MCD-L0 ";
   if(gIsIndi==1 && z > e)
   {
      double zbuf[];
      if(GetMacdBuffer(z, zbuf, 3) && ArraySize(zbuf)>=2)
      {
         if(zbuf[1] >= 0.0)
            CreateBuyStopSplit(HARGA_BUY_STOP, lot, magic, cmt);
         else
            CreateSellStopSplit(HARGA_SELL_STOP, lot, magic, cmt);
      }
   }
   else
   {
      CreateBuyStopSplit(HARGA_BUY_STOP, lot, magic, cmt);
      CreateSellStopSplit(HARGA_SELL_STOP, lot, magic, cmt);
   }
}

void DispatchKendali(ulong ticket, double tp, double sl)
{
   if(tp==0) return;

   long ip = (long)MathFloor(tp);
   double frac = NormalizeDouble(tp - (double)ip, 2);
   int digits = (ip<=0)?1:(int)MathFloor(MathLog10((double)ip))+1;

   if(digits==2)
   {
      switch((int)ip)
      {
         case 12: CreateParamLS();      ResetKendaliTP(ticket); return;
         case 13: DeleteAllParamLS();   ResetKendaliTP(ticket); return;
         case 19: Handle_TP19();        ResetKendaliTP(ticket); return;
         case 20: Handle_TP20();        ResetKendaliTP(ticket); return;
         case 99:                       ResetKendaliTP(ticket); return;
         default:                       ResetKendaliTP(ticket); return;
      }
   }

   if(digits==4 && ip>=8100 && ip<=8799)
   {
      int ELL = (int)(ip-8000);
      int E  = ELL/100;
      int LL = ELL%100;
      double loopTP = (double)E*11000.0 + (double)LL + frac;
      CreateLoopLSWithTP(loopTP);
      ResetKendaliTP(ticket);
      return;
   }

   if(digits==6 && ip>=811100 && ip<=899999)
   {
      double loopTP = tp - 800000.0;
      CreateLoopLSWithTP(loopTP);
      ResetKendaliTP(ticket);
      return;
   }

   if(digits==3 || digits==4 || digits==5)
   {
      ProcessNewOrderCommand(tp, sl);
      ResetKendaliTP(ticket);
      return;
   }

   ResetKendaliTP(ticket);
}

double TotalProfitAll()
{
   double tot=0;
   int pt = PositionsTotal();
   for(int i=0;i<pt;i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk==0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      tot += PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return tot;
}

void CheckExitTriggers()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(gExitUSD>0)
   {
      if(TotalProfitAll()>gExitUSD){ CloseAllExceptKendali(); return; }
   }
   if(gExitBid>0)
   {
      if(bid>gExitBid){ CloseAllExceptKendali(); return; }
   }
   if(gExitBidMin>0)
   {
      if(bid<gExitBidMin){ CloseAllExceptKendali(); return; }
   }
}

void RunExitProfitAll()
{
   if(gExitPct<=0) return;

   double profits[MAX_MAGIC_TRACK];
   int    counts[MAX_MAGIC_TRACK];
   ArrayInitialize(profits,0);
   ArrayInitialize(counts,0);

   int pt = PositionsTotal();
   for(int i=0;i<pt;i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk==0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long mg = (long)PositionGetInteger(POSITION_MAGIC);
      for(int m=0;m<gMagicCount;m++)
      {
         if(gMagics[m].magic==mg)
         {
            profits[m] += PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
            counts[m]++;
            break;
         }
      }
   }

   double target = AccountInfoDouble(ACCOUNT_BALANCE)*gExitPct/100.0;
   for(int m=0;m<gMagicCount;m++)
   {
      if(counts[m]>0 && profits[m]>target)
         CloseMagic(gMagics[m].magic);
   }
}

#include "indi_ichimoku.h"

void RebuildMagicsFromExistingOrders()
{
   int pt = PositionsTotal();
   for(int i=0;i<pt;i++)
   {
      ulong tk = PositionGetTicket(i);
      if(tk==0) continue;
      if(!PositionSelectByTicket(tk)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long mg = (long)PositionGetInteger(POSITION_MAGIC);
      if(mg==MAGIC_KENDALI || mg==0) continue;
      string cmt = PositionGetString(POSITION_COMMENT);
      if(StringFind(cmt,":MCD")<0 && StringFind(cmt,":ICH")<0) continue;
      if(FindMagic(mg)<0)
         RegisterMagic(mg, PositionGetDouble(POSITION_VOLUME), gXLot);
   }
   int ot = OrdersTotal();
   for(int i=0;i<ot;i++)
   {
      ulong tk = OrderGetTicket(i);
      if(tk==0) continue;
      if(!OrderSelect(tk)) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      long mg = (long)OrderGetInteger(ORDER_MAGIC);
      if(mg==MAGIC_KENDALI || mg==0) continue;
      string cmt = OrderGetString(ORDER_COMMENT);
      if(StringFind(cmt,":MCD")<0 && StringFind(cmt,":ICH")<0) continue;
      if(FindMagic(mg)<0)
         RegisterMagic(mg, OrderGetDouble(ORDER_VOLUME_CURRENT), gXLot);
   }
}

int OnInit()
{
   trade.SetExpertMagicNumber(MAGIC_KENDALI);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();

   ArrayInitialize(gMacdHandles, INVALID_HANDLE);
   ArrayInitialize(gFractalHandles, INVALID_HANDLE);
   ArrayInitialize(gIchiHandles, INVALID_HANDLE);
   ArrayInitialize(gLastPeakTimePerE, 0);
   ArrayInitialize(gLastValleyTimePerE, 0);
   ArrayInitialize(gLastPeakIdxPerE, 0);
   ArrayInitialize(gLastValleyIdxPerE, 0);
   ArrayInitialize(gLastPeakPricePerE, 0);
   ArrayInitialize(gLastValleyPricePerE, 0);

   gIsIndi           = InpIsIndi;
   gExitPct          = InpExitPct;
   gXLot             = InpXLot;
   gExitUSD          = InpExitUSD;
   gExitBid          = InpExitBid;
   gExitBidMin       = InpExitBidMin;
   gAddTemen         = InpAddTemen;
   gAllowPeakNegatif = InpAllowPeakNegatif;
   gLoopPerDay       = InpLoopPerDay;
   gStartTrade       = InpStartTrade;
   gEndTrade         = InpEndTrade;
   gWIBOffset        = InpWIBOffset;
   gIchiShiftX       = InpIchiShiftX;
   gIchiBuffer       = InpIchiBuffer;
   gMMRatio          = InpMMRatio;
   gSplitLot         = InpSplitLot;
   gTR               = InpTR;
   gDetekPuncak      = InpDetekPuncak;

   gMagicCount = 0;
   RebuildMagicsFromExistingOrders();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   for(int i=1;i<=7;i++)
      if(gMacdHandles[i]!=INVALID_HANDLE)
         IndicatorRelease(gMacdHandles[i]);
   for(int i=1;i<=7;i++)
      if(gFractalHandles[i]!=INVALID_HANDLE)
         IndicatorRelease(gFractalHandles[i]);
   ichi_ReleaseHandles();
}

void OnTick()
{
   EnsureLimitKendali();
   SyncParamsFromMagicParam();
   CheckLoopLS();
   CheckBTAutoOrder();

   ulong kTicket; double kTP, kSL;
   if(GetLimitKendali(kTicket,kTP,kSL))
   {
      if((long)MathFloor(kTP)==99)
         return;
      if(kTP!=0)
         DispatchKendali(kTicket, kTP, kSL);
   }

   CheckExitTriggers();

   datetime now = TimeCurrent();
   if(now!=gLastMacdCheck)
   {
      gLastMacdCheck = now;
      PruneTriggered();
      if(gIsIndi==1)
         RunIndiLogicAll();
      else if(gIsIndi==2)
         RunIchiLogicAll();
   }

   RunExitProfitAll();
}
//+------------------------------------------------------------------+