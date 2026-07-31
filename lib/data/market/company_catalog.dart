/// A bundled catalogue of well-known US-listed companies and ETFs.
///
/// This is NOT a market listing and never decides what can be traded — the
/// provider's own symbol lookup does that, and any plausible ticker can still
/// be typed directly. What this buys is the two things a lookup API is bad at:
/// recognising a company by name when the learner does not know the ticker,
/// and surviving a typo. Both matter for an audience meeting these names for
/// the first time.
///
/// Kept deliberately to household names. A student typing "disney" or "coca
/// cola" should land somewhere sensible; exhaustive coverage is the provider's
/// job.
library;

/// One catalogue entry. [aliases] carries the names people actually type —
/// "google" for Alphabet, "facebook" for Meta — which is most of the value
/// here.
class Company {
  const Company(this.symbol, this.name, [this.aliases = const <String>[]]);

  final String symbol;
  final String name;
  final List<String> aliases;
}

const List<Company> kCompanyCatalog = <Company>[
  // Mega-cap technology
  Company('AAPL', 'Apple Inc'),
  Company('MSFT', 'Microsoft Corp'),
  Company('GOOGL', 'Alphabet Inc', <String>['google']),
  Company('AMZN', 'Amazon.com Inc', <String>['amazon']),
  Company('META', 'Meta Platforms Inc', <String>['facebook', 'instagram']),
  Company('NVDA', 'NVIDIA Corp'),
  Company('TSLA', 'Tesla Inc'),
  Company('AVGO', 'Broadcom Inc'),
  Company('ORCL', 'Oracle Corp'),
  Company('CRM', 'Salesforce Inc'),
  Company('ADBE', 'Adobe Inc'),
  Company('AMD', 'Advanced Micro Devices Inc'),
  Company('INTC', 'Intel Corp'),
  Company('CSCO', 'Cisco Systems Inc'),
  Company('QCOM', 'Qualcomm Inc'),
  Company('TXN', 'Texas Instruments Inc'),
  Company('MU', 'Micron Technology Inc'),
  Company('IBM', 'International Business Machines Corp'),
  Company('NOW', 'ServiceNow Inc'),
  Company('UBER', 'Uber Technologies Inc'),
  Company('ABNB', 'Airbnb Inc'),
  Company('SHOP', 'Shopify Inc'),
  Company('SPOT', 'Spotify Technology SA'),
  Company('SNAP', 'Snap Inc', <String>['snapchat']),
  Company('PINS', 'Pinterest Inc'),
  Company('RBLX', 'Roblox Corp'),
  Company('COIN', 'Coinbase Global Inc'),
  Company('PLTR', 'Palantir Technologies Inc'),
  Company('DELL', 'Dell Technologies Inc'),
  Company('HPQ', 'HP Inc', <String>['hewlett packard']),
  Company('SONY', 'Sony Group Corp'),
  Company('TSM', 'Taiwan Semiconductor Manufacturing Co'),
  Company('ARM', 'Arm Holdings plc'),

  // Media and entertainment
  Company('NFLX', 'Netflix Inc'),
  Company('DIS', 'Walt Disney Co', <String>['disney']),
  Company('WBD', 'Warner Bros Discovery Inc', <String>['warner brothers']),
  Company('PARA', 'Paramount Global'),
  Company('EA', 'Electronic Arts Inc'),
  Company('TTWO', 'Take-Two Interactive Software Inc'),
  Company('LYV', 'Live Nation Entertainment Inc'),

  // Finance
  Company('JPM', 'JPMorgan Chase & Co', <String>['jp morgan', 'chase']),
  Company('BAC', 'Bank of America Corp'),
  Company('WFC', 'Wells Fargo & Co'),
  Company('GS', 'Goldman Sachs Group Inc'),
  Company('MS', 'Morgan Stanley'),
  Company('C', 'Citigroup Inc', <String>['citibank', 'citi']),
  Company('BRK.B', 'Berkshire Hathaway Inc Class B', <String>['berkshire']),
  Company('V', 'Visa Inc'),
  Company('MA', 'Mastercard Inc'),
  Company('AXP', 'American Express Co', <String>['amex']),
  Company('PYPL', 'PayPal Holdings Inc'),
  Company('SQ', 'Block Inc', <String>['square', 'cash app']),
  Company('SCHW', 'Charles Schwab Corp'),
  Company('BLK', 'BlackRock Inc'),
  Company('COF', 'Capital One Financial Corp'),

  // Healthcare and pharma
  Company('JNJ', 'Johnson & Johnson'),
  Company('UNH', 'UnitedHealth Group Inc'),
  Company('LLY', 'Eli Lilly & Co'),
  Company('PFE', 'Pfizer Inc'),
  Company('MRK', 'Merck & Co Inc'),
  Company('ABBV', 'AbbVie Inc'),
  Company('TMO', 'Thermo Fisher Scientific Inc'),
  Company('ABT', 'Abbott Laboratories'),
  Company('AMGN', 'Amgen Inc'),
  Company('MRNA', 'Moderna Inc'),
  Company('CVS', 'CVS Health Corp'),

  // Consumer
  Company('WMT', 'Walmart Inc'),
  Company('COST', 'Costco Wholesale Corp'),
  Company('TGT', 'Target Corp'),
  Company('HD', 'Home Depot Inc'),
  Company('LOW', "Lowe's Companies Inc"),
  Company('NKE', 'Nike Inc'),
  Company('SBUX', 'Starbucks Corp'),
  Company('MCD', "McDonald's Corp", <String>['mcdonalds']),
  Company('KO', 'Coca-Cola Co', <String>['coke', 'coca cola']),
  Company('PEP', 'PepsiCo Inc', <String>['pepsi']),
  Company('PG', 'Procter & Gamble Co'),
  Company('CL', 'Colgate-Palmolive Co'),
  Company('UL', 'Unilever plc'),
  Company('MDLZ', 'Mondelez International Inc'),
  Company('KHC', 'Kraft Heinz Co'),
  Company('GIS', 'General Mills Inc'),
  Company('CMG', 'Chipotle Mexican Grill Inc'),
  Company('YUM', 'Yum! Brands Inc', <String>['kfc', 'taco bell', 'pizza hut']),
  Company('DPZ', "Domino's Pizza Inc", <String>['dominos']),
  Company('LULU', 'Lululemon Athletica Inc'),
  Company('EL', 'Estee Lauder Companies Inc'),

  // Industrials, energy, transport
  Company('BA', 'Boeing Co'),
  Company('CAT', 'Caterpillar Inc'),
  Company('GE', 'General Electric Co'),
  Company('F', 'Ford Motor Co'),
  Company('GM', 'General Motors Co'),
  Company('RIVN', 'Rivian Automotive Inc'),
  Company('LCID', 'Lucid Group Inc'),
  Company('DAL', 'Delta Air Lines Inc'),
  Company('UAL', 'United Airlines Holdings Inc'),
  Company('LUV', 'Southwest Airlines Co'),
  Company('UPS', 'United Parcel Service Inc'),
  Company('FDX', 'FedEx Corp'),
  Company('XOM', 'Exxon Mobil Corp', <String>['exxon']),
  Company('CVX', 'Chevron Corp'),
  Company('COP', 'ConocoPhillips'),
  Company('NEE', 'NextEra Energy Inc'),
  Company('LMT', 'Lockheed Martin Corp'),
  Company('RTX', 'RTX Corp', <String>['raytheon']),
  Company('DE', 'Deere & Co', <String>['john deere']),
  Company('MMM', '3M Co'),
  Company('HON', 'Honeywell International Inc'),

  // Telecom, travel, other
  Company('T', 'AT&T Inc'),
  Company('VZ', 'Verizon Communications Inc'),
  Company('TMUS', 'T-Mobile US Inc'),
  Company('CMCSA', 'Comcast Corp'),
  Company('MAR', 'Marriott International Inc'),
  Company('HLT', 'Hilton Worldwide Holdings Inc'),
  Company('BKNG', 'Booking Holdings Inc', <String>['booking.com']),
  Company('DASH', 'DoorDash Inc'),
  Company('LYFT', 'Lyft Inc'),
  Company('ZM', 'Zoom Communications Inc'),
  Company('ROKU', 'Roku Inc'),
  Company('ETSY', 'Etsy Inc'),
  Company('EBAY', 'eBay Inc'),
  Company('TJX', 'TJX Companies Inc'),
  Company('SPGI', 'S&P Global Inc'),

  // ETFs a learner is likely to meet
  Company('SPY', 'SPDR S&P 500 ETF Trust', <String>['s&p 500', 'sp500']),
  Company('VOO', 'Vanguard S&P 500 ETF'),
  Company('IVV', 'iShares Core S&P 500 ETF'),
  Company('QQQ', 'Invesco QQQ Trust', <String>['nasdaq 100']),
  Company('DIA', 'SPDR Dow Jones Industrial Average ETF', <String>['dow']),
  Company('IWM', 'iShares Russell 2000 ETF', <String>['russell 2000']),
  Company('VTI', 'Vanguard Total Stock Market ETF'),
  Company('VT', 'Vanguard Total World Stock ETF'),
  Company('AGG', 'iShares Core US Aggregate Bond ETF'),
  Company('TLT', 'iShares 20+ Year Treasury Bond ETF'),
  Company('GLD', 'SPDR Gold Shares', <String>['gold']),
  Company('SLV', 'iShares Silver Trust', <String>['silver']),
  Company('USO', 'United States Oil Fund', <String>['oil']),
  Company('VXX', 'iPath Series B S&P 500 VIX Futures ETN', <String>['vix']),
  Company('ARKK', 'ARK Innovation ETF'),
  Company('EEM', 'iShares MSCI Emerging Markets ETF'),
  Company('EFA', 'iShares MSCI EAFE ETF'),
  Company('XLF', 'Financial Select Sector SPDR Fund'),
  Company('XLE', 'Energy Select Sector SPDR Fund'),
  Company('XLK', 'Technology Select Sector SPDR Fund'),
];
