//
//  IdeviceFFI.h
//  Reynard
//
//  Created by Minh Ton on 11/3/26.
//

#ifndef IdeviceFFI_h
#define IdeviceFFI_h

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/socket.h>

typedef struct AdapterHandle AdapterHandle;
typedef struct DebugProxyHandle DebugProxyHandle;
typedef struct DebugserverCommandHandle DebugserverCommandHandle;
typedef struct HeartbeatClientHandle HeartbeatClientHandle;
typedef struct IdeviceHandle IdeviceHandle;
typedef struct IdevicePairingFile IdevicePairingFile;
typedef struct IdeviceProviderHandle IdeviceProviderHandle;
typedef struct ImageMounterHandle ImageMounterHandle;
typedef struct LockdowndClientHandle LockdowndClientHandle;
typedef struct ProcessControlHandle ProcessControlHandle;
typedef struct RemoteServerHandle RemoteServerHandle;
typedef struct RpPairingFileHandle RpPairingFileHandle;
typedef struct RsdHandshakeHandle RsdHandshakeHandle;

typedef void *plist_t;

typedef struct IdeviceFfiError {
  int32_t code;
  int32_t sub_code;
  const char *message;
} IdeviceFfiError;

IdeviceFfiError *idevice_pairing_file_read(const char *path,
                                           IdevicePairingFile **pairing_file);
void idevice_pairing_file_free(IdevicePairingFile *pairing_file);

IdeviceFfiError *rp_pairing_file_read(const char *path,
                                      RpPairingFileHandle **out);
void rp_pairing_file_free(RpPairingFileHandle *handle);

IdeviceFfiError *
tunnel_create_rppairing(const struct sockaddr *addr, socklen_t addr_len,
                        const char *hostname, RpPairingFileHandle *pairing_file,
                        const char *(*pin_callback)(void *context),
                        void *pin_context, AdapterHandle **out_adapter,
                        RsdHandshakeHandle **out_handshake);

IdeviceFfiError *idevice_tcp_provider_new(const struct sockaddr *ip,
                                          IdevicePairingFile *pairing_file,
                                          const char *label,
                                          IdeviceProviderHandle **provider);
IdeviceFfiError *
idevice_provider_get_pairing_file(IdeviceProviderHandle *provider,
                                  IdevicePairingFile **pairing_file);
void idevice_provider_free(IdeviceProviderHandle *provider);

IdeviceFfiError *lockdownd_connect(IdeviceProviderHandle *provider,
                                   LockdowndClientHandle **client);
IdeviceFfiError *lockdownd_start_session(LockdowndClientHandle *client,
                                         IdevicePairingFile *pairing_file);
IdeviceFfiError *lockdownd_start_service(LockdowndClientHandle *client,
                                         const char *identifier, uint16_t *port,
                                         bool *ssl);
IdeviceFfiError *lockdownd_get_value(LockdowndClientHandle *client,
                                     const char *key, const char *domain,
                                     plist_t *out_plist);
void lockdownd_client_free(LockdowndClientHandle *handle);

IdeviceFfiError *lockdownd_connect_rsd(AdapterHandle *provider,
                                       RsdHandshakeHandle *handshake,
                                       LockdowndClientHandle **client);

IdeviceFfiError *image_mounter_connect(IdeviceProviderHandle *provider,
                                       ImageMounterHandle **client);
IdeviceFfiError *image_mounter_connect_rsd(AdapterHandle *provider,
                                           RsdHandshakeHandle *handshake,
                                           ImageMounterHandle **client);
void image_mounter_free(ImageMounterHandle *handle);
IdeviceFfiError *image_mounter_copy_devices(ImageMounterHandle *client,
                                            plist_t **devices,
                                            size_t *devices_len);
IdeviceFfiError *image_mounter_lookup_image(ImageMounterHandle *client,
                                            const char *image_type,
                                            uint8_t **signature,
                                            size_t *signature_len);
IdeviceFfiError *image_mounter_mount_developer(ImageMounterHandle *client,
                                               const uint8_t *image,
                                               size_t image_len,
                                               const uint8_t *signature,
                                               size_t signature_len);
IdeviceFfiError *image_mounter_mount_personalized(
    ImageMounterHandle *client, IdeviceProviderHandle *provider,
    const uint8_t *image, size_t image_len, const uint8_t *trust_cache,
    size_t trust_cache_len, const uint8_t *build_manifest,
    size_t build_manifest_len, const void *info_plist, uint64_t unique_chip_id);
IdeviceFfiError *image_mounter_mount_personalized_rsd(
    ImageMounterHandle *client, AdapterHandle *provider,
    RsdHandshakeHandle *handshake, const uint8_t *image, size_t image_len,
    const uint8_t *trust_cache, size_t trust_cache_len,
    const uint8_t *build_manifest, size_t build_manifest_len,
    const void *info_plist, uint64_t unique_chip_id);

IdeviceFfiError *heartbeat_connect(IdeviceProviderHandle *provider,
                                   HeartbeatClientHandle **client);
IdeviceFfiError *heartbeat_connect_rsd(AdapterHandle *provider,
                                       RsdHandshakeHandle *handshake,
                                       HeartbeatClientHandle **client);
IdeviceFfiError *heartbeat_get_marco(HeartbeatClientHandle *client,
                                     uint64_t interval, uint64_t *new_interval);
IdeviceFfiError *heartbeat_send_polo(HeartbeatClientHandle *client);
void heartbeat_client_free(HeartbeatClientHandle *handle);

void adapter_free(AdapterHandle *handle);

void rsd_handshake_free(RsdHandshakeHandle *handle);

IdeviceFfiError *remote_server_connect_rsd(AdapterHandle *provider,
                                           RsdHandshakeHandle *handshake,
                                           RemoteServerHandle **handle);
void remote_server_free(RemoteServerHandle *handle);

IdeviceFfiError *process_control_new(RemoteServerHandle *server,
                                     ProcessControlHandle **handle);
void process_control_free(ProcessControlHandle *handle);
IdeviceFfiError *
process_control_disable_memory_limit(ProcessControlHandle *handle,
                                     uint64_t pid);

IdeviceFfiError *debug_proxy_connect_rsd(AdapterHandle *provider,
                                         RsdHandshakeHandle *handshake,
                                         DebugProxyHandle **handle);
void debug_proxy_free(DebugProxyHandle *handle);
IdeviceFfiError *debug_proxy_send_command(DebugProxyHandle *handle,
                                          DebugserverCommandHandle *command,
                                          char **response);
IdeviceFfiError *debug_proxy_read_response(DebugProxyHandle *handle,
                                           char **response);
IdeviceFfiError *debug_proxy_send_ack(DebugProxyHandle *handle);
void debug_proxy_set_ack_mode(DebugProxyHandle *handle, int enabled);

DebugserverCommandHandle *debugserver_command_new(const char *name,
                                                  const char *const *argv,
                                                  uintptr_t argv_count);
void debugserver_command_free(DebugserverCommandHandle *command);

void idevice_data_free(uint8_t *data, uintptr_t len);
void idevice_error_free(IdeviceFfiError *err);
void idevice_string_free(char *string);

void plist_free(plist_t plist);
void plist_get_string_val(plist_t node, char **val);
void plist_get_uint_val(plist_t node, uint64_t *val);

#endif /* IdeviceFFI_h */
