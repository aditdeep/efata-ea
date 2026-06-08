//+------------------------------------------------------------------+
//| indi_ichimoku.h - Modul indikator Ichimoku (isIndi==2)
//+------------------------------------------------------------------+
#ifndef __INDI_ICHIMOKU_H__
#define __INDI_ICHIMOKU_H__

#define ICHI_TENKAN   5
#define ICHI_KIJUN    13
#define ICHI_SENKOUB  26

bool IchiWasTriggered(ulong ticket)
{
   for(int i=0;i<gTriggeredCount;i++)
      if(gTriggered[i]==ticket) return true;
   return false;
}

void IchiMarkTriggered(ulong ticket)
{
   if(IchiWasTriggered(ticket)) return;
   ArrayResize(gTriggered, gTriggeredCount+1);
   gTriggered[gTriggeredCount++] = ticket;
}

double IchiStopsDist()
{
   long lvl = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double d  = (double)lvl * _Point;
   if(d < _Point) d = _Point;
   return d + _Point;
}

double ClampBuyStopPrice(double want)
{
   double minP = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + IchiStopsDist();
   if(want < minP) want = minP;
   return NormPrice(want);
}

double ClampSellStopPrice(double want)
{
   double maxP = SymbolInfoDouble(_Symbol, SYMBOL_BID) - IchiStopsDist();
   if(want > maxP) want = maxP;
   return NormPrice(want);
}

bool CreateBuyMarket(double lot, long magic, string cmt)
{
   return CreateBuyMarketSplit(lot, magic, cmt);
}

bool CreateSellMarket(double lot, long magic, string cmt)
{
   return CreateSellMarketSplit(lot, magic, cmt);
}

void ichi_InitHandles()
{
   ArrayInitialize(gIchiHandles, INVALID_HANDLE);
}

void ichi_ReleaseHandles()
{
   for(int i=1;i<=7;i++)
      if(gIchiHandles[i]!=INVALID_HANDLE)
      {
         IndicatorRelease(gIchiHandles[i]);
         gIchiHandles[i]=INVALID_HANDLE;
      }
}

int GetIchiHandle(int tfDigit)
{
   if(tfDigit<1 || tfDigit>7) return INVALID_HANDLE;
   if(gIchiHandles[tfDigit]==INVALID_HANDLE)
      gIchiHandles[tfDigit] = iIchimoku(_Symbol, MapTF(tfDigit),
                                        ICHI_TENKAN, ICHI_KIJUN, ICHI_SENKOUB);
   return gIchiHandles[tfDigit];
}

bool GetIchiKijun(int tfDigit, int shift, double &val)
{
   int h = GetIchiHandle(tfDigit);
   if(h==INVALID_HANDLE) return false;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(h,1,shift,1,b)<=0) return false;
   val=b[0];
   return true;
}

bool GetIchiSpanA(int tfDigit, int shift, double &val)
{
   int h = GetIchiHandle(tfDigit);
   if(h==INVALID_HANDLE) return false;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(h,2,shift,1,b)<=0) return false;
   val=b[0];
   return true;
}

bool GetIchiSpanB(int tfDigit, int shift, double &val)
{
   int h = GetIchiHandle(tfDigit);
   if(h==INVALID_HANDLE) return false;
   double b[];
   ArraySetAsSeries(b,true);
   if(CopyBuffer(h,3,shift,1,b)<=0) return false;
   val=b[0];
   return true;
}

bool GetKumo(int tfDigit, double &topKumo, double &botKumo)
{
   double a,b;
   if(!GetIchiSpanA(tfDigit,1,a)) return false;
   if(!GetIchiSpanB(tfDigit,1,b)) return false;
   topKumo=MathMax(a,b);
   botKumo=MathMin(a,b);
   return true;
}

bool GetClose1(int tfDigit, double &c)
{
   double cl[];
   ArraySetAsSeries(cl,true);
   if(CopyClose(_Symbol,MapTF(tfDigit),1,1,cl)<=0) return false;
   c=cl[0];
   return true;
}

double GetRecentHigh(int tfDigit, int lookback)
{
   double h[];
   ArraySetAsSeries(h,true);
   int copied = CopyHigh(_Symbol, MapTF(tfDigit), 1, lookback, h);
   if(copied<=0) return 0;
   double mx=h[0];
   for(int i=1;i<copied;i++) if(h[i]>mx) mx=h[i];
   return mx;
}

double GetRecentLow(int tfDigit, int lookback)
{
   double l[];
   ArraySetAsSeries(l,true);
   int copied = CopyLow(_Symbol, MapTF(tfDigit), 1, lookback, l);
   if(copied<=0) return 0;
   double mn=l[0];
   for(int i=1;i<copied;i++) if(l[i]<mn) mn=l[i];
   return mn;
}

int IchiSignal(int tfDigit, double &kijun, double &topKumo, double &botKumo)
{
   kijun=0; topKumo=0; botKumo=0;
   double c1;
   if(!GetClose1(tfDigit,c1)) return 0;
   if(!GetIchiKijun(tfDigit,1,kijun)) return 0;
   if(!GetKumo(tfDigit,topKumo,botKumo)) return 0;
   if(c1 < kijun && c1 < botKumo) return -1;
   if(c1 > kijun && c1 > topKumo) return +1;
   return 0;
}

double GetAcuanBS(int tfDigit, double kijun, double topKumo, double bid,
                  bool farFromKijun, double bufP)
{
   double base = 0;
   if(farFromKijun && kijun>0)
   {
      base = kijun;
   }
   else
   {
      if(topKumo>0 && topKumo > (bid + IchiStopsDist()))
         base = topKumo;
      else
      {
         double swHigh = GetRecentHigh(tfDigit, ICHI_KIJUN);
         if(swHigh > (bid + IchiStopsDist()))
            base = swHigh;
         else if(kijun>0)
            base = kijun;
      }
   }
   return ClampBuyStopPrice(base + bufP);
}

double GetAcuanSS(int tfDigit, double kijun, double botKumo, double bid,
                  bool farFromKijun, double bufP)
{
   double base = 0;
   if(farFromKijun && kijun>0)
   {
      base = kijun;
   }
   else
   {
      if(botKumo>0 && botKumo < (bid - IchiStopsDist()))
         base = botKumo;
      else
      {
         double swLow = GetRecentLow(tfDigit, ICHI_KIJUN);
         if(swLow > 0 && swLow < (bid - IchiStopsDist()))
            base = swLow;
         else if(kijun>0)
            base = kijun;
      }
   }
   return ClampSellStopPrice(base - bufP);
}

void RunIchiLogicMagic(int idx)
{
   long   magic = gMagics[idx].magic;
   int    eTF   = gMagics[idx].eTF;
   double xlot  = gMagics[idx].xlot;

   if(!IsWithinTradingHours()) return;

   double kijun, topKumo, botKumo;
   int sig = IchiSignal(eTF, kijun, topKumo, botKumo);

   ScanResult sc;
   sc.Scan(magic);

   double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double bufP = gIchiBuffer * _Point;
   double xDist= gIchiShiftX * _Point;
   bool farFromKijun = (kijun>0) && (MathAbs(bid-kijun) >= xDist);

   if(sc.nBuy==0 && sc.nSell==0 && sc.nBS==0 && sc.nSS==0)
   {
      double iLot = gMagics[idx].initLot;
      if(iLot > 0 && sig != 0)
      {
         if(sig==-1)
         {
            string cmt = IntegerToString(magic)+":ICH-L0 ";
            if(CreateSellMarket(iLot, magic, cmt)) sc.Scan(magic);
         }
         else if(sig==+1)
         {
            string cmt = IntegerToString(magic)+":ICH-L0 ";
            if(CreateBuyMarket(iLot, magic, cmt)) sc.Scan(magic);
         }
      }
   }

   for(int s=0;s<sc.nSell;s++)
   {
      ulong  T  = sc.sellT[s];
      int    Lx = GetLevelFromComment(sc.sellC[s]);
      if(Lx<0) Lx=0;
      double sL = sc.sellL[s];
      string lwTag = "-L"+IntegerToString(Lx+1)+":"+IntegerToString((long)T);
      bool found=false;
      for(int b=0;b<sc.nBS;b++)  if(StringFind(sc.bsC[b],lwTag)>=0){found=true;break;}
      if(!found) for(int b=0;b<sc.nBuy;b++) if(StringFind(sc.buyC[b],lwTag)>=0){found=true;break;}
      if(!found && IchiWasTriggered(T)) found=true;
      if(!found && (MAX_LEVEL<=0||(Lx+1)<=MAX_LEVEL))
      {
         string cmt=IntegerToString(magic)+":ICH-L"+IntegerToString(Lx+1)+":"+IntegerToString((long)T);
         if(CreateBuyStopSplit(HARGA_BUY_STOP, sL*xlot, magic, cmt)){ IchiMarkTriggered(T); sc.Scan(magic); }
      }
   }

   for(int b=0;b<sc.nBuy;b++)
   {
      ulong  T  = sc.buyT[b];
      int    Lx = GetLevelFromComment(sc.buyC[b]);
      if(Lx<0) Lx=0;
      double bL = sc.buyL[b];
      string lwTag = "-L"+IntegerToString(Lx+1)+":"+IntegerToString((long)T);
      bool found=false;
      for(int s=0;s<sc.nSS;s++)   if(StringFind(sc.ssC[s],lwTag)>=0){found=true;break;}
      if(!found) for(int s=0;s<sc.nSell;s++) if(StringFind(sc.sellC[s],lwTag)>=0){found=true;break;}
      if(!found && IchiWasTriggered(T)) found=true;
      if(!found && (MAX_LEVEL<=0||(Lx+1)<=MAX_LEVEL))
      {
         string cmt=IntegerToString(magic)+":ICH-L"+IntegerToString(Lx+1)+":"+IntegerToString((long)T);
         if(CreateSellStopSplit(HARGA_SELL_STOP, bL*xlot, magic, cmt)){ IchiMarkTriggered(T); sc.Scan(magic); }
      }
   }

   if(sc.nBS>0)
   {
      double t = GetAcuanBS(eTF, kijun, topKumo, bid, farFromKijun, bufP);
      if(t>0)
      {
         for(int b=0;b<sc.nBS;b++)
         {
            if(CountColons(sc.bsC[b])!=2 || StringFind(sc.bsC[b],"-T")>=0) continue;
            double tol = _Point * 15;
            if(MathAbs(sc.bsP[b]-t) > tol)
            {
               trade.SetExpertMagicNumber(magic);
               trade.OrderModify(sc.bsT[b], t, 0, 0, ORDER_TIME_GTC, 0);
            }
         }
      }
   }

   if(sc.nSS>0)
   {
      double t = GetAcuanSS(eTF, kijun, botKumo, bid, farFromKijun, bufP);
      if(t>0)
      {
         for(int s=0;s<sc.nSS;s++)
         {
            if(CountColons(sc.ssC[s])!=2 || StringFind(sc.ssC[s],"-T")>=0) continue;
            double tol = _Point * 15;
            if(MathAbs(sc.ssP[s]-t) > tol)
            {
               trade.SetExpertMagicNumber(magic);
               trade.OrderModify(sc.ssT[s], t, 0, 0, ORDER_TIME_GTC, 0);
            }
         }
      }
   }
}

void RunIchiLogicAll()
{
   for(int i=0;i<gMagicCount;i++)
      RunIchiLogicMagic(i);
}

#endif
