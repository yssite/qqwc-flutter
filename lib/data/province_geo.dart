/// 中国省级行政区粗粒度边界（离线兜底用）。
///
/// 只在系统 Geocoder 不可用（无网络 / 无服务）时用来把经纬度映射到省份，
/// 结果仅用于就近节点匹配，不参与任何精确展示。
library;

class _ProvinceBox {
  const _ProvinceBox(
    this.name,
    this.latMin,
    this.latMax,
    this.lngMin,
    this.lngMax,
  );

  final String name;
  final double latMin;
  final double latMax;
  final double lngMin;
  final double lngMax;

  bool contains(double lat, double lng) =>
      lat >= latMin && lat <= latMax && lng >= lngMin && lng <= lngMax;

  double get area => (latMax - latMin) * (lngMax - lngMin);
}

/// 按面积从小到大排列，保证直辖市 / 特别行政区优先命中。
final List<_ProvinceBox> _boxes = [
  const _ProvinceBox('澳门', 22.05, 22.22, 113.52, 113.60),
  const _ProvinceBox('香港', 22.15, 22.56, 113.83, 114.44),
  const _ProvinceBox('上海', 30.68, 31.88, 120.85, 122.12),
  const _ProvinceBox('北京', 39.44, 41.06, 115.42, 117.51),
  const _ProvinceBox('天津', 38.55, 40.25, 116.70, 118.06),
  const _ProvinceBox('海南', 18.10, 20.20, 108.60, 111.05),
  const _ProvinceBox('宁夏', 35.20, 39.40, 104.28, 107.66),
  const _ProvinceBox('台湾', 21.85, 25.35, 119.95, 122.05),
  const _ProvinceBox('重庆', 28.16, 32.20, 105.28, 110.20),
  const _ProvinceBox('江苏', 30.75, 35.10, 116.30, 121.95),
  const _ProvinceBox('浙江', 27.00, 31.20, 118.00, 123.15),
  const _ProvinceBox('安徽', 29.40, 34.65, 114.90, 119.65),
  const _ProvinceBox('福建', 23.50, 28.30, 115.80, 120.45),
  const _ProvinceBox('江西', 24.50, 30.08, 113.57, 118.48),
  const _ProvinceBox('湖北', 29.00, 33.27, 108.35, 116.13),
  const _ProvinceBox('湖南', 24.60, 30.13, 108.78, 114.26),
  const _ProvinceBox('广东', 20.20, 25.52, 109.75, 117.19),
  const _ProvinceBox('广西', 20.90, 26.40, 104.45, 112.05),
  const _ProvinceBox('贵州', 24.60, 29.20, 103.60, 109.60),
  const _ProvinceBox('河南', 31.40, 36.37, 110.35, 116.65),
  const _ProvinceBox('山东', 34.40, 38.40, 114.80, 122.70),
  const _ProvinceBox('山西', 34.60, 40.75, 110.20, 114.60),
  const _ProvinceBox('陕西', 31.70, 39.58, 105.50, 111.25),
  const _ProvinceBox('辽宁', 38.70, 43.50, 118.80, 125.80),
  const _ProvinceBox('吉林', 40.90, 46.30, 121.60, 131.30),
  const _ProvinceBox('黑龙江', 43.40, 53.60, 121.10, 135.10),
  const _ProvinceBox('河北', 36.00, 42.60, 113.40, 119.90),
  const _ProvinceBox('四川', 26.03, 34.30, 97.35, 108.55),
  const _ProvinceBox('云南', 21.13, 29.25, 97.52, 106.20),
  const _ProvinceBox('甘肃', 32.60, 42.80, 92.30, 108.70),
  const _ProvinceBox('青海', 31.60, 39.20, 89.35, 103.07),
  const _ProvinceBox('西藏', 26.85, 36.50, 78.40, 99.10),
  const _ProvinceBox('新疆', 34.30, 49.20, 73.50, 96.40),
  const _ProvinceBox('内蒙古', 37.40, 53.30, 97.20, 126.10),
]..sort((a, b) => a.area.compareTo(b.area));

/// 经纬度 → 省份简称；落在所有框外时返回空串。
String provinceOf(double lat, double lng) {
  if (lat == 0 && lng == 0) return '';
  for (final box in _boxes) {
    if (box.contains(lat, lng)) return box.name;
  }
  return '';
}
