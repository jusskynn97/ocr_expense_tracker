import '../entities/expense_category.dart';

/// Phân loại chi tiêu bằng heuristic từ khoá (không cần model AI).
class CategoryClassifier {
  const CategoryClassifier._();

  static const Map<ExpenseCategory, List<String>> _keywords =
      <ExpenseCategory, List<String>>{
    ExpenseCategory.food: <String>[
      'quán', 'quan an', 'cafe', 'cà phê', 'coffee', 'nhà hàng', 'nha hang',
      'restaurant', 'cơm', 'com tam', 'phở', 'pho ', 'bún', 'bun bo', 'bánh mì',
      'bánh mỳ', 'trà sữa', 'tra sua', 'milk tea', 'highlands', 'phúc long',
      'starbucks', 'kfc', 'lotteria', 'mcdonald', 'pizza', 'burger', 'buffet',
      'chè', 'kem', 'sinh tố', 'nước ép', 'đồ ăn', 'food', 'siêu thị',
      'sieuthi', 'vinmart', 'winmart', 'co.opmart', 'big c', 'go!', 'circle k',
      'gs25', 'family mart', 'familymart', 'minimart', 'tạp hoá', 'tap hoa',
      'grab food', 'shopeefood', 'baemin', 'bánh ngọt', 'tiệm bánh',
    ],
    ExpenseCategory.study: <String>[
      'sách', 'sach ', 'nhà sách', 'nha sach', 'book', 'bookstore', 'fahasa',
      'học phí', 'hoc phi', 'khóa học', 'khoa hoc', 'course', 'udemy',
      'coursera', 'edx', 'văn phòng phẩm', 'van phong pham', 'stationery',
      'photocopy', 'in ấn', 'in an', 'thư viện', 'library', 'tài liệu',
      'giáo trình', 'giaotrinh', 'notebook', 'sổ tay', 'bút', 'đồ dùng học tập',
    ],
    ExpenseCategory.travel: <String>[
      'grab', 'be group', 'xanh sm', 'taxi', 'vé', 've xe', 'vé tàu',
      'ticket', 'xe buýt', 'xe bus', 'bus ', 'metro', 'xe lửa', 'tàu hoả',
      'tàu', 'máy bay', 'flight', 'vietjet', 'vietnam airlines', 'bamboo',
      'xăng', 'xang ', 'petrolimex', 'petrol', 'cây xăng', 'gửi xe', 'giu xe',
      'parking', 'cầu đường', 'cao tốc', 'phà', 'phí gửi xe', 'be ride',
      'gojek', 'be  ', 'shipper',
    ],
    ExpenseCategory.gear: <String>[
      'laptop', 'điện thoại', 'dien thoai', 'phone', 'cellphones', 'fpt shop',
      'thế giới di động', 'tgdd', 'phụ kiện', 'phu kien', 'accessory', 'gear',
      'màn hình', 'man hinh', 'chuột', 'chuot ', 'bàn phím', 'ban phim',
      'tai nghe', 'headphone', 'earbuds', 'apple', 'samsung', 'asus', 'acer',
      'dell', 'lenovo', 'logitech', 'crucial', 'kingston', 'ssd', 'ram ',
      'chip', 'vga', 'gear shop', 'shopee', 'lazada', 'tiki', 'điện tử',
      'dien tu', 'camera', 'webcam', 'sạc', 'cáp', 'usb', 'hub',
    ],
    ExpenseCategory.entertainment: <String>[
      'cgv', 'lotte cinema', 'galaxy cinema', 'bhd', 'cinema', 'rạp', 'rap ',
      'phim', 'movie', 'netflix', 'spotify', 'youtube premium', 'steam',
      'playstation', 'game', 'karaoke', 'bar ', 'pub', 'club', 'concert',
      'ca nhạc', 'giải trí', 'giai tri', 'bida', 'bowling', 'công viên',
      'khu vui chơi', 'xem phim',
    ],
  };

  /// Trả về nhóm phù hợp nhất dựa trên tên cửa hàng và text hoá đơn.
  static ExpenseCategory classify(
    String? merchant,
    String rawText, {
    ExpenseCategory fallback = ExpenseCategory.food,
  }) {
    final String merchantHaystack = _normalize(merchant ?? '');
    final String textHaystack = _normalize(rawText);

    ExpenseCategory best = fallback;
    int bestScore = 0;

    _keywords.forEach((ExpenseCategory category, List<String> keywords) {
      int score = 0;
      for (final String keyword in keywords) {
        final String needle = _normalize(keyword);
        if (needle.trim().isEmpty) continue;
        if (merchantHaystack.contains(needle)) score += 3;
        if (textHaystack.contains(needle)) score += 1;
      }
      if (score > bestScore) {
        bestScore = score;
        best = category;
      }
    });

    return best;
  }

  static String _normalize(String value) => value.toLowerCase();
}
