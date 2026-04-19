class AppConstants {
  static const int transferTtlHours = 24;
  static const int meteredNetworkWarnThresholdBytes = 100 * 1024 * 1024;
  static const int maxTransferSizeBytes = 1024 * 1024 * 1024;
  static const String shortCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const int shortCodeLength = 8;

  /// `transfer_files.storage_path` sentinel when bytes are delivered over LAN P2P (no Storage object).
  static const String lanOnlyStoragePathPrefix = 'lan-only:';

  /// Same-subnet discovery (multicast). Wi‑Fi Direct / BLE can extend this channel later.
  static const String nearbyMulticastAddress = '239.18.4.26';
  static const int nearbyDiscoveryUdpPort = 55671;
  static const int nearbyDiscoveryTimeoutMs = 2800;
  static const int nearbyTcpConnectTimeoutMs = 8000;
}
