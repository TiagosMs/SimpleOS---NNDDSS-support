#!/bin/sh
# Charge LED is gpio-leds battery_charging = PMU gpio0 pin 21.
# leds-gpio turns it off on S3 (no retain-state-suspended). Hold the pin
# ourselves so it stays on while USB is charging.

CHARGE_GPIO=21

charge_plugged() {
	for p in /sys/class/power_supply/*; do
		[ -d "$p" ] || continue
		if [ -r "$p/online" ] && [ "$(cat "$p/online" 2>/dev/null)" = "1" ]; then
			return 0
		fi
		if [ -r "$p/status" ]; then
			case "$(cat "$p/status" 2>/dev/null)" in
				Charging|Full|"Not charging") return 0 ;;
			esac
		fi
	done
	return 1
}

charge_led_on() {
	if [ -e /sys/class/leds/battery_charging/brightness ]; then
		echo 1 > /sys/class/leds/battery_charging/brightness 2>/dev/null || true
	fi
}

charge_led_hold() {
	echo 1 > /sys/class/anbernic_misc/workled_sleep 2>/dev/null || true
	charge_plugged || return 0
	charge_led_on
	if [ -e /sys/bus/platform/drivers/leds-gpio/gpio-leds ]; then
		echo gpio-leds > /sys/bus/platform/drivers/leds-gpio/unbind 2>/dev/null || true
	fi
	if [ ! -e /sys/class/gpio/gpio${CHARGE_GPIO} ]; then
		echo "$CHARGE_GPIO" > /sys/class/gpio/export 2>/dev/null || true
	fi
	if [ -d /sys/class/gpio/gpio${CHARGE_GPIO} ]; then
		echo out > /sys/class/gpio/gpio${CHARGE_GPIO}/direction 2>/dev/null || true
		echo 1 > /sys/class/gpio/gpio${CHARGE_GPIO}/value 2>/dev/null || true
	fi
}

charge_led_release() {
	if [ -e /sys/class/gpio/gpio${CHARGE_GPIO} ]; then
		echo "$CHARGE_GPIO" > /sys/class/gpio/unexport 2>/dev/null || true
	fi
	if [ ! -e /sys/bus/platform/drivers/leds-gpio/gpio-leds ]; then
		echo gpio-leds > /sys/bus/platform/drivers/leds-gpio/bind 2>/dev/null || true
	fi
	echo 0 > /sys/class/anbernic_misc/workled_sleep 2>/dev/null || true
	charge_plugged && charge_led_on || true
}
