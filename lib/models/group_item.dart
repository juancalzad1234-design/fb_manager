// ==========================================
// MODEL
// ==========================================
class GroupItem {
  String url;
  String status; // 'good', 'regular', 'bad', 'none'

  GroupItem({required this.url, this.status = 'none'});

  GroupItem copy() => GroupItem(url: url, status: status);

  factory GroupItem.fromJson(dynamic json) {
    if (json is String) {
      return GroupItem(url: json, status: 'none');
    }
    if (json is Map) {
      final url = (json['url'] ?? json['link'] ?? '').toString();
      final status = (json['status'] ?? 'none').toString();
      return GroupItem(url: url, status: status);
    }
    return GroupItem(url: '', status: 'none');
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'status': status,
  };
}
