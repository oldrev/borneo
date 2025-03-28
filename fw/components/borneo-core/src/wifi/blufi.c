
#include <stdlib.h>
#include <string.h>

#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/event_groups.h>

#include <esp_system.h>
#include <esp_wifi.h>
#include <esp_event.h>
#include <esp_log.h>
#include <nvs_flash.h>

#if CONFIG_BT_BLE_BLUFI_ENABLE

#include <esp_bt.h>
#include <esp_blufi.h>
#include <esp_bt_defs.h>
#include <esp_gap_ble_api.h>
#include <esp_bt_main.h>
#include <esp_bt_device.h>

#include "./blufi.h"
#include "./blufi-security.h"

#include <borneo/common.h>
#include <borneo/system.h>

static void _event_callback(esp_blufi_cb_event_t event, esp_blufi_cb_param_t* param);

// clang-format off
static uint8_t _service_uuid128[32] = {
    /* LSB <--------------------------------------------------------------------------------> MSB */
    //first uuid, 16bit, [12],[13] is the value
    0xfb, 0x34, 0x9b, 0x5f, 0x80, 0x00, 0x00, 0x80, 0x00, 0x10, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00,
};
// clang-format on

// static uint8_t test_manufacturer[TEST_MANUFACTURER_DATA_LEN] =  {0x12, 0x23, 0x45, 0x56};
static esp_ble_adv_data_t _adv_data = {
    .set_scan_rsp = false,
    .include_name = true,
    .include_txpower = true,
    .min_interval = 0x0006, // slave connection min interval, Time = min_interval * 1.25 msec
    .max_interval = 0x0010, // slave connection max interval, Time = max_interval * 1.25 msec
    .appearance = 0x00,
    .manufacturer_len = 0,
    .p_manufacturer_data = NULL,
    .service_data_len = 0,
    .p_service_data = NULL,
    .service_uuid_len = 16,
    .p_service_uuid = _service_uuid128,
    .flag = 0x6,
};

static esp_ble_adv_params_t _adv_params = {
    .adv_int_min = 0x100,
    .adv_int_max = 0x100,
    .adv_type = ADV_TYPE_IND,
    .own_addr_type = BLE_ADDR_TYPE_PUBLIC,
    //.peer_addr            =
    //.peer_addr_type       =
    .channel_map = ADV_CHNL_ALL,
    .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
};

#define WIFI_LIST_NUM 10

static wifi_config_t sta_config;
static wifi_config_t ap_config;

/* FreeRTOS event group to signal when we are connected & ready to make a request */
static EventGroupHandle_t _wifi_event_group;

/* The event group allows multiple bits for each event,
   but we only care about one event - are we connected
   to the AP with an IP? */
const int CONNECTED_BIT = BIT0;

/* store the station info for send back to phone */
static bool gl_sta_connected = false;
static bool ble_is_connected = false;
static uint8_t gl_sta_bssid[6];
static uint8_t gl_sta_ssid[32];
static int gl_sta_ssid_len;

/* connect infor*/
static uint8_t _server_if;
static uint16_t _conn_id;

static esp_blufi_callbacks_t _callbacks = {
    .event_cb = _event_callback,
    .negotiate_data_handler = blufi_dh_negotiate_data_handler,
    .encrypt_func = blufi_aes_encrypt,
    .decrypt_func = blufi_aes_decrypt,
    .checksum_func = blufi_crc_checksum,
};

static void ip_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    wifi_mode_t mode;

    switch (event_id) {

    case IP_EVENT_STA_GOT_IP: {
        esp_blufi_extra_info_t info;

        xEventGroupSetBits(_wifi_event_group, CONNECTED_BIT);
        esp_wifi_get_mode(&mode);

        memset(&info, 0, sizeof(esp_blufi_extra_info_t));
        memcpy(info.sta_bssid, gl_sta_bssid, 6);
        info.sta_bssid_set = true;
        info.sta_ssid = gl_sta_ssid;
        info.sta_ssid_len = gl_sta_ssid_len;
        if (ble_is_connected == true) {
            esp_blufi_send_wifi_conn_report(mode, ESP_BLUFI_STA_CONN_SUCCESS, 0, &info);
        }
        else {
            BLUFI_INFO("BLUFI BLE is not connected yet\n");
        }
        // 已经成功获得了 IP 地址，关掉 BLE
        esp_blufi_close(_server_if, _conn_id);
        // esp_bluedroid_disable();
        // esp_bluedroid_deinit();
        esp_blufi_profile_deinit();
        esp_bt_controller_disable();
        esp_bt_controller_deinit();
        BLUFI_INFO("Bluetooth has been turned off.");
    } break;

    default:
        break;
    }

    return;
}

static void wifi_event_handler(void* arg, esp_event_base_t event_base, int32_t event_id, void* event_data)
{
    wifi_event_sta_connected_t* event;
    wifi_mode_t mode;

    switch (event_id) {

    case WIFI_EVENT_STA_START: {
        esp_wifi_connect();
    } break;

    case WIFI_EVENT_STA_CONNECTED: {
        gl_sta_connected = true;
        event = (wifi_event_sta_connected_t*)event_data;
        memcpy(gl_sta_bssid, event->bssid, 6);
        memcpy(gl_sta_ssid, event->ssid, event->ssid_len);
        gl_sta_ssid_len = event->ssid_len;
    } break;

    case WIFI_EVENT_STA_DISCONNECTED: {
        /* This is a workaround as ESP32 WiFi libs don't currently
           auto-reassociate. */
        gl_sta_connected = false;
        memset(gl_sta_ssid, 0, 32);
        memset(gl_sta_bssid, 0, 6);
        gl_sta_ssid_len = 0;
        esp_wifi_connect();
        xEventGroupClearBits(_wifi_event_group, CONNECTED_BIT);
    } break;

    case WIFI_EVENT_AP_START: {
        esp_wifi_get_mode(&mode);

        /* TODO: get config or information of softap, then set to report extra_info */
        if (ble_is_connected == true) {
            if (gl_sta_connected) {
                esp_blufi_send_wifi_conn_report(mode, ESP_BLUFI_STA_CONN_SUCCESS, 0, NULL);
            }
            else {
                esp_blufi_send_wifi_conn_report(mode, ESP_BLUFI_STA_CONN_FAIL, 0, NULL);
            }
        }
        else {
            BLUFI_INFO("BLUFI BLE is not connected yet\n");
        }
    } break;

    case WIFI_EVENT_SCAN_DONE: {
        uint16_t apCount = 0;
        esp_wifi_scan_get_ap_num(&apCount);
        if (apCount == 0) {
            BLUFI_INFO("Nothing AP found");
            break;
        }
        wifi_ap_record_t* ap_list = (wifi_ap_record_t*)malloc(sizeof(wifi_ap_record_t) * apCount);
        if (!ap_list) {
            BLUFI_ERROR("malloc error, ap_list is NULL");
            break;
        }
        if (esp_wifi_scan_get_ap_records(&apCount, ap_list) != 0) {
            break;
        }
        esp_blufi_ap_record_t* blufi_ap_list = (esp_blufi_ap_record_t*)malloc(apCount * sizeof(esp_blufi_ap_record_t));
        if (!blufi_ap_list) {
            if (ap_list) {
                free(ap_list);
            }
            BLUFI_ERROR("malloc error, blufi_ap_list is NULL");
            break;
        }
        for (int i = 0; i < apCount; ++i) {
            blufi_ap_list[i].rssi = ap_list[i].rssi;
            memcpy(blufi_ap_list[i].ssid, ap_list[i].ssid, sizeof(ap_list[i].ssid));
        }

        if (ble_is_connected == true) {
            esp_blufi_send_wifi_list(apCount, blufi_ap_list);
        }
        else {
            BLUFI_INFO("BLUFI BLE is not connected yet\n");
        }

        esp_wifi_scan_stop();
        free(ap_list);
        free(blufi_ap_list);
    } break;

    default:
        break;
    }

    return;
}

static void _event_callback(esp_blufi_cb_event_t event, esp_blufi_cb_param_t* param)
{
    /* actually, should post to blufi_task handle the procedure,
     * now, as a example, we do it more simply */
    switch (event) {

    case ESP_BLUFI_EVENT_INIT_FINISH: {
        BLUFI_INFO("BLUFI init finish\n");

        esp_ble_gap_set_device_name(CONFIG_BORNEO_DEVICE_NAME_DEFAULT);
        esp_ble_gap_config_adv_data(&_adv_data);
    } break;

    case ESP_BLUFI_EVENT_DEINIT_FINISH: {
        BLUFI_INFO("BLUFI deinit finish\n");
    } break;

    case ESP_BLUFI_EVENT_BLE_CONNECT: {
        BLUFI_INFO("BLUFI ble connect\n");
        ble_is_connected = true;
        _server_if = param->connect.server_if;
        _conn_id = param->connect.conn_id;
        esp_ble_gap_stop_advertising();
        blufi_security_init();
    } break;

    case ESP_BLUFI_EVENT_BLE_DISCONNECT: {
        BLUFI_INFO("BLUFI ble disconnect\n");
        ble_is_connected = false;
        blufi_security_deinit();
        esp_ble_gap_start_advertising(&_adv_params);
    } break;

    case ESP_BLUFI_EVENT_SET_WIFI_OPMODE: {
        BLUFI_INFO("BLUFI Set WIFI opmode %d\n", param->wifi_mode.op_mode);
        if (esp_wifi_set_mode(param->wifi_mode.op_mode) != 0) {
            BLUFI_ERROR("Failed to set WiFi mode");
        }
    } break;

    case ESP_BLUFI_EVENT_REQ_CONNECT_TO_AP: {
        BLUFI_INFO("BLUFI requset wifi connect to AP\n");
        /* there is no wifi callback when the device has already connected to this wifi
        so disconnect wifi before connection.
        */
        esp_wifi_disconnect();
        esp_wifi_connect();
    } break;

    case ESP_BLUFI_EVENT_REQ_DISCONNECT_FROM_AP: {
        BLUFI_INFO("BLUFI requset wifi disconnect from AP\n");
        esp_wifi_disconnect();
    } break;

    case ESP_BLUFI_EVENT_REPORT_ERROR: {
        BLUFI_ERROR("BLUFI report error, error code %d\n", param->report_error.state);
        esp_blufi_send_error_info(param->report_error.state);
    } break;

    case ESP_BLUFI_EVENT_GET_WIFI_STATUS: {
        wifi_mode_t mode;
        esp_blufi_extra_info_t info;

        esp_wifi_get_mode(&mode);

        if (gl_sta_connected) {
            memset(&info, 0, sizeof(esp_blufi_extra_info_t));
            memcpy(info.sta_bssid, gl_sta_bssid, 6);
            info.sta_bssid_set = true;
            info.sta_ssid = gl_sta_ssid;
            info.sta_ssid_len = gl_sta_ssid_len;
            esp_blufi_send_wifi_conn_report(mode, ESP_BLUFI_STA_CONN_SUCCESS, 0, &info);
        }
        else {
            esp_blufi_send_wifi_conn_report(mode, ESP_BLUFI_STA_CONN_FAIL, 0, NULL);
        }
        BLUFI_INFO("BLUFI get wifi status from AP\n");
    } break;

    case ESP_BLUFI_EVENT_RECV_SLAVE_DISCONNECT_BLE: {
        BLUFI_INFO("blufi close a gatt connection");
        esp_blufi_close(_server_if, _conn_id);
    } break;

    case ESP_BLUFI_EVENT_DEAUTHENTICATE_STA:
        /* TODO */
        break;

    case ESP_BLUFI_EVENT_RECV_STA_BSSID: {
        memcpy(sta_config.sta.bssid, param->sta_bssid.bssid, 6);
        sta_config.sta.bssid_set = 1;
        esp_wifi_set_config(WIFI_IF_STA, &sta_config);
        BLUFI_INFO("Recv STA BSSID %s\n", sta_config.sta.ssid);
    } break;

    case ESP_BLUFI_EVENT_RECV_STA_SSID: {
        strncpy((char*)sta_config.sta.ssid, (char*)param->sta_ssid.ssid, param->sta_ssid.ssid_len);
        sta_config.sta.ssid[param->sta_ssid.ssid_len] = '\0';
        esp_wifi_set_config(WIFI_IF_STA, &sta_config);
        BLUFI_INFO("Recv STA SSID %s\n", sta_config.sta.ssid);
    } break;

    case ESP_BLUFI_EVENT_RECV_STA_PASSWD: {
        strncpy((char*)sta_config.sta.password, (char*)param->sta_passwd.passwd, param->sta_passwd.passwd_len);
        sta_config.sta.password[param->sta_passwd.passwd_len] = '\0';
        esp_wifi_set_config(WIFI_IF_STA, &sta_config);
        BLUFI_INFO("Recv STA PASSWORD %s\n", sta_config.sta.password);
    } break;

    case ESP_BLUFI_EVENT_RECV_SOFTAP_SSID: {
        strncpy((char*)ap_config.ap.ssid, (char*)param->softap_ssid.ssid, param->softap_ssid.ssid_len);
        ap_config.ap.ssid[param->softap_ssid.ssid_len] = '\0';
        ap_config.ap.ssid_len = param->softap_ssid.ssid_len;
        esp_wifi_set_config(WIFI_IF_AP, &ap_config);
        BLUFI_INFO("Recv SOFTAP SSID %s, ssid len %d\n", ap_config.ap.ssid, ap_config.ap.ssid_len);
    } break;

    case ESP_BLUFI_EVENT_RECV_SOFTAP_PASSWD: {
        strncpy((char*)ap_config.ap.password, (char*)param->softap_passwd.passwd, param->softap_passwd.passwd_len);
        ap_config.ap.password[param->softap_passwd.passwd_len] = '\0';
        esp_wifi_set_config(WIFI_IF_AP, &ap_config);
        BLUFI_INFO("Recv SOFTAP PASSWORD %s len = %d\n", ap_config.ap.password, param->softap_passwd.passwd_len);
    } break;

    case ESP_BLUFI_EVENT_RECV_SOFTAP_MAX_CONN_NUM: {
        if (param->softap_max_conn_num.max_conn_num > 4) {
            return;
        }
        ap_config.ap.max_connection = param->softap_max_conn_num.max_conn_num;
        esp_wifi_set_config(WIFI_IF_AP, &ap_config);
        BLUFI_INFO("Recv SOFTAP MAX CONN NUM %d\n", ap_config.ap.max_connection);
    } break;

    case ESP_BLUFI_EVENT_RECV_SOFTAP_AUTH_MODE: {
        if (param->softap_auth_mode.auth_mode >= WIFI_AUTH_MAX) {
            return;
        }
        ap_config.ap.authmode = param->softap_auth_mode.auth_mode;
        esp_wifi_set_config(WIFI_IF_AP, &ap_config);
        BLUFI_INFO("Recv SOFTAP AUTH MODE %u\n", ap_config.ap.authmode);
    } break;

    case ESP_BLUFI_EVENT_RECV_SOFTAP_CHANNEL: {
        if (param->softap_channel.channel > 13) {
            return;
        }
        ap_config.ap.channel = param->softap_channel.channel;
        esp_wifi_set_config(WIFI_IF_AP, &ap_config);
        BLUFI_INFO("Recv SOFTAP CHANNEL %d\n", ap_config.ap.channel);
    } break;

    case ESP_BLUFI_EVENT_GET_WIFI_LIST: {
        wifi_scan_config_t scanConf = { .ssid = NULL, .bssid = NULL, .channel = 0, .show_hidden = false };
        esp_wifi_scan_start(&scanConf, true);
        break;
    }

    case ESP_BLUFI_EVENT_RECV_CUSTOM_DATA: {
        BLUFI_INFO("Recv Custom Data %ld\n", param->custom_data.data_len);
        esp_log_buffer_hex("Custom Data", param->custom_data.data, param->custom_data.data_len);
    } break;

    case ESP_BLUFI_EVENT_RECV_USERNAME:
        /* Not handle currently */
        break;

    case ESP_BLUFI_EVENT_RECV_CA_CERT:
        /* Not handle currently */
        break;

    case ESP_BLUFI_EVENT_RECV_CLIENT_CERT:
        /* Not handle currently */
        break;

    case ESP_BLUFI_EVENT_RECV_SERVER_CERT:
        /* Not handle currently */
        break;

    case ESP_BLUFI_EVENT_RECV_CLIENT_PRIV_KEY:
        /* Not handle currently */
        break;

    case ESP_BLUFI_EVENT_RECV_SERVER_PRIV_KEY:
        /* Not handle currently */
        break;

    default:
        break;
    }
}

static void blufi_gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t* param)
{
    switch (event) {

    case ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT: {
        esp_ble_gap_start_advertising(&_adv_params);
    } break;

    default:
        break;
    }
}

int bo_wifi_blufi_init()
{
    _wifi_event_group = xEventGroupCreate();

    BO_TRY(esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, &wifi_event_handler, NULL));
    BO_TRY(esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, &ip_event_handler, NULL));

    return 0;
}

int bo_wifi_blufi_start()
{
// 同时用 WiFi 和蓝牙需要打开 WiFi 休眠模式
#if CONFIG_BT_ENABLED
    BO_TRY(esp_wifi_set_ps(WIFI_PS_MIN_MODEM));
#endif // CONFIG_BT_ENABLED

    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    BO_TRY(esp_bt_controller_init(&bt_cfg));

    BO_TRY(esp_bt_controller_enable(ESP_BT_MODE_BLE));
    BO_TRY(esp_bluedroid_init());
    BO_TRY(esp_bluedroid_enable());

    BLUFI_INFO("BD ADDR: " ESP_BD_ADDR_STR "\n", ESP_BD_ADDR_HEX(esp_bt_dev_get_address()));
    BLUFI_INFO("BLUFI VERSION %04x\n", esp_blufi_get_version());

    BO_TRY(esp_ble_gap_register_callback(blufi_gap_event_handler));
    BO_TRY(esp_blufi_register_callbacks(&_callbacks));
    BO_TRY(esp_blufi_profile_init());

    return 0;
}

#endif // CONFIG_BT_BLE_ENABLED