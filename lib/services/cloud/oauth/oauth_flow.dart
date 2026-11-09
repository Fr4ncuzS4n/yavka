import 'oauth_flow_stub.dart'
    if (dart.library.io) 'oauth_flow_io.dart'
    if (dart.library.js_interop) 'oauth_flow_web.dart'
    as platform;
import 'oauth_models.dart';

/// Создаёт OAuth-поток для текущей платформы.
///
/// * Android/iOS/Linux/macOS/Windows — loopback-flow с локальным сервером.
/// * Web — Google Identity Services (token model).
OAuthFlow createOAuthFlow() => platform.createPlatformOAuthFlow();
