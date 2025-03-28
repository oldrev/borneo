#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#define LYFI_LED_MAX_POWER 100
#define LYFI_LEDC_SCHEDULER_ITEMS_CAPACITY 48

#define LYFI_LED_CHANNEL_COUNT CONFIG_LYFI_LED_CHANNEL_COUNT

typedef uint16_t led_duty_t;
typedef uint8_t led_color_t[LYFI_LED_CHANNEL_COUNT];
typedef led_duty_t led_duties_t[LYFI_LED_CHANNEL_COUNT];

enum led_mode {
    LED_MODE_NORMAL = 0,
    LED_MODE_DIMMING = 1,
    LED_MODE_NIGHTLIGHT = 2,
    LED_MODE_PREVIEW = 3,

    LED_MODE_COUNT,
};

struct led_scheduler_item {
    uint32_t instant;
    led_color_t color;
};

struct led_scheduler {
    size_t item_count;
    struct led_scheduler_item items[LYFI_LEDC_SCHEDULER_ITEMS_CAPACITY];
};

struct led_factory_settings {
    uint16_t pwm_freq; ///< The frequency of PWM signals
};

struct led_user_settings {
    uint8_t scheduler_enabled; ///< Whether the scheduling mode is enabled
    uint16_t nightlight_duration; ///< Night lighting mode duration (in seconds)
    struct led_scheduler scheduler; ///< Scheduling scheduler for scheduled mode
    led_color_t manual_color; ///< Manual dimming power settings for each channel
    uint8_t cie1931_enabled; ///< Whether the CIE1931 correction is enabled
};

struct led_status {
    uint8_t mode; ///< Current mode
    led_color_t color; ///< Current hardware LED power percentage for each channel
    int64_t nightlight_off_time; ///< Time point after temporary lighting mode to turn off, this time point is when
                                 ///< fading out starts
    time_t preview_mode_clock; ///< Clock for preview mode
    led_color_t color_to_resume; ///< Color to be resumed

    led_color_t fade_start_color;
    led_color_t fade_end_color;
    int64_t fade_start_time_ms; ///< Time point of fading started
    uint32_t fade_duration_ms; ///< The duration of fading
};

int led_init();

uint8_t led_channel_count();

void led_blank();

int led_set_color(const uint8_t* color);

int led_get_color(uint8_t* color);

int led_get_duties(led_duty_t* duties);

uint8_t led_get_channel_power(uint8_t ch);

int led_set_channel_power(uint8_t ch, uint8_t value);

int led_set_power(const led_color_t color);

int led_set_schedule(const struct led_scheduler_item* items, size_t count);
const struct led_scheduler* led_get_schedule();

const struct led_user_settings* led_get_settings();

const struct led_status* led_get_status();

int led_switch_mode(uint8_t mode);

bool led_is_blank();

int led_set_scheduler_enabled(bool enabled);

void led_set_nightlight_duration(uint16_t duration);
int32_t led_get_nightlight_remaining();

#ifdef __cplusplus
}
#endif