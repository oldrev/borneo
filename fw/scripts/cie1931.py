import math
import numpy as np
import datetime

PWM_DUTY_MAX = 4095
BRIGHT_LEVEL_MAX = 4095


def generate_cie1931_lut(size: int):
    def cie1931_normalized(L):
        if L <= 8:
            y = L / 903.3
        else:
            y = ((L + 16) / 116) ** 3

        max_L = 100.0
        if max_L <= 8:
            max_y = max_L / 903.3
        else:
            max_y = ((max_L + 16) / 116) ** 3

        return y / max_y

    lut = []
    input_max = size - 1

    for i in range(size):
        L = (i / input_max) * 100.0

        normalized_value = cie1931_normalized(L)

        pwm_value = round(normalized_value * PWM_DUTY_MAX)
        lut.append(min(pwm_value, PWM_DUTY_MAX))

    return lut


def generate_logarithmic_lut(size: int, gamma: float = 2.2):
    """Generate logarithmic dimming curve lookup table (using exponential form)"""
    lut = []
    for level in range(size):
        if level == 0:
            pwm = 0
        else:
            normalized = level / (size - 1)  # Normalize to 0-1
            if normalized > 0:
                corrected = math.log(1 + normalized * (math.e - 1)) ** gamma
            else:
                corrected = 0.0
            pwm = round(corrected * PWM_DUTY_MAX)
            pwm = max(0, min(pwm, PWM_DUTY_MAX))
        lut.append(pwm)
    return lut


def generate_exponential_lut(size: int):
    # From https://github.com/orgs/borneo-iot/discussions/5
    lut = []

    # Replace 4095 by the amount of PWM steps
    # Calculate the r variable (only needs to be done once at setup)
    R = ((size - 1) * math.log10(2)) / (math.log10(PWM_DUTY_MAX))

    for i in range(size):
        if i == 0:
            brightness = 0
        elif i == size - 1:
            brightness = PWM_DUTY_MAX
        else:
            brightness = (PWM_DUTY_MAX * pow(2, i / R)) / PWM_DUTY_MAX
        lut.append(round(brightness))
    return lut


def generate_gamma_lut(size: int, gamma: float = 2.6):
    """Generate gamma correction lookup table
    Args:
        size: number of brightness levels
        gamma: gamma value (typical 2.2 for displays)
    """
    lut = []
    for level in range(size):
        if level == 0:
            pwm = 0
        else:
            # Gamma correction formula
            normalized = level / (size - 1)  # normalize to 0-1
            corrected = normalized ** gamma  # apply gamma correction
            pwm = round(corrected * PWM_DUTY_MAX)
            # Clamp to valid range
            pwm = max(0, min(pwm, PWM_DUTY_MAX))
        lut.append(pwm)
    return lut


def generate_lut_header(lut_size):
    """Generate C header file containing both LUTs"""
    cie_lut = generate_cie1931_lut(lut_size)
    assert (len(cie_lut) == lut_size)
    log_lut = generate_logarithmic_lut(lut_size)
    assert (len(log_lut) == lut_size)
    exp_lut = generate_exponential_lut(lut_size)
    assert (len(exp_lut) == lut_size)
    gamma_lut = generate_gamma_lut(lut_size, gamma=2.2)  # Standard gamma 2.2
    assert (len(gamma_lut) == lut_size)

    header = f"""// Auto-generated brightness lookup tables
// Generation time: {datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
// LUT size: {lut_size}

#include <stdlib.h>
#include <stdbool.h>
#include <time.h>

// CIE 1931 brightness curve lookup table (perceptual uniform)
const led_duty_t LED_CORLUT_CIE1931[] = {{
    {', '.join(map(str, cie_lut))},
}};

// Logarithmic dimming curve lookup table
const led_duty_t LED_CORLUT_LOG[] = {{
    {', '.join(map(str, log_lut))},
}};

// Logarithmic dimming curve lookup table
const led_duty_t LED_CORLUT_EXP[] = {{
    {', '.join(map(str, exp_lut))},
}};

// Gamma correction lookup table (GAMMA=2.2)
const led_duty_t LED_CORLUT_GAMMA[] = {{
    {', '.join(map(str, gamma_lut))},
}};

"""
    return header


if __name__ == "__main__":
    # User-configurable LUT size
    lut_size = BRIGHT_LEVEL_MAX + 1

    # Generate header file content
    header_content = generate_lut_header(lut_size)

    # Write to file
    with open("brightness_lut.h", "w") as f:
        f.write(header_content)

    print("Lookup tables generated in brightness_lut.h")
