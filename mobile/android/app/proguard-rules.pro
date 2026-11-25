# WorkManager(google_mobile_ads가 사용)의 Room 데이터베이스는 리플렉션으로 기본 생성자를 부른다.
# AGP 9의 R8은 규칙에 적지 않은 생성자를 지우는데 Room 2.2.5의 기본 규칙에는 생성자가 없어
# 릴리스 앱이 실행 직후 종료된다 (Failed to create an instance of androidx.work.impl.WorkDatabase).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
