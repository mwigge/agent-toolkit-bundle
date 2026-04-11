# Time Series Analysis — Reference Links

## Python Libraries
- https://www.statsmodels.org/stable/tsa.html — statsmodels time series analysis: ARIMA, SARIMA, STL, Holt-Winters
- https://www.statsmodels.org/stable/generated/statsmodels.tsa.seasonal.STL.html — STL decomposition: Seasonal and Trend decomposition using Loess
- https://facebook.github.io/prophet/ — Prophet: Facebook's forecasting library for business time series
- https://www.sktime.net/en/stable/ — sktime: unified framework for time series classification, regression, forecasting
- https://pandas.pydata.org/docs/user_guide/timeseries.html — pandas time series: date_range, resample, rolling, shift, periods

## Databases & Query Patterns
- https://docs.influxdata.com/influxdb/v2/ — InfluxDB v2: time series database, Flux query language
- https://prometheus.io/docs/prometheus/latest/querying/basics/ — PromQL basics: instant vectors, range vectors, functions
- https://prometheus.io/docs/prometheus/latest/querying/functions/ — PromQL functions: rate(), irate(), increase(), histogram_quantile()

## Anomaly Detection
- https://en.wikipedia.org/wiki/Interquartile_range — IQR method for outlier detection: Q1 - 1.5*IQR, Q3 + 1.5*IQR
- https://www.statsmodels.org/stable/generated/statsmodels.tsa.stattools.adfuller.html — Augmented Dickey-Fuller test: stationarity testing
