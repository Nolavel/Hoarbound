#ifndef HOARBOUND_FROST_PROGRESSION_HPP
#define HOARBOUND_FROST_PROGRESSION_HPP

#include <algorithm>
#include <array>
#include <cmath>
#include <string>

namespace hoarbound::frost {

constexpr double kMinimumDurationSeconds = 0.1;

class FrostProgression {
public:
	explicit FrostProgression(double duration_seconds = 6.5, bool auto_playing = true)
		: duration_seconds_(sanitize_duration(duration_seconds)), auto_playing_(auto_playing) {}

	void set_duration(double duration_seconds) {
		duration_seconds_ = sanitize_duration(duration_seconds);
		elapsed_seconds_ = amount_ * duration_seconds_;
	}

	double duration() const {
		return duration_seconds_;
	}

	void set_amount(double amount) {
		amount_ = std::clamp(amount, 0.0, 1.0);
		elapsed_seconds_ = amount_ * duration_seconds_;
		auto_playing_ = false;
	}

	double amount() const {
		return amount_;
	}

	void restart() {
		elapsed_seconds_ = 0.0;
		amount_ = 0.0;
		auto_playing_ = true;
	}

	void set_auto_playing(bool enabled) {
		auto_playing_ = enabled && amount_ < 1.0;
	}

	bool is_auto_playing() const {
		return auto_playing_;
	}

	double advance(double delta_seconds) {
		if (!auto_playing_) {
			return amount_;
		}

		elapsed_seconds_ = std::min(
			duration_seconds_,
			elapsed_seconds_ + std::max(0.0, delta_seconds));
		amount_ = elapsed_seconds_ / duration_seconds_;
		if (elapsed_seconds_ >= duration_seconds_) {
			auto_playing_ = false;
		}
		return amount_;
	}

private:
	static double sanitize_duration(double duration_seconds) {
		return std::max(kMinimumDurationSeconds, duration_seconds);
	}

	double duration_seconds_ = 6.5;
	double elapsed_seconds_ = 0.0;
	double amount_ = 0.0;
	bool auto_playing_ = true;
};

inline int amount_thousandths(const FrostProgression &progression) {
	return static_cast<int>(std::lround(progression.amount() * 1000.0));
}

inline std::string reference_trace() {
	FrostProgression progression(4.0);
	std::array<int, 7> samples{};
	samples[0] = amount_thousandths(progression);
	progression.advance(1.0);
	samples[1] = amount_thousandths(progression);
	progression.advance(1.0);
	samples[2] = amount_thousandths(progression);
	progression.set_amount(1.5);
	samples[3] = amount_thousandths(progression);
	progression.restart();
	samples[4] = amount_thousandths(progression);
	progression.set_duration(0.0);
	progression.advance(0.05);
	samples[5] = amount_thousandths(progression);
	progression.advance(0.05);
	samples[6] = amount_thousandths(progression);

	std::string trace;
	for (std::size_t index = 0; index < samples.size(); ++index) {
		if (index > 0) {
			trace += ',';
		}
		trace += std::to_string(samples[index]);
	}
	return trace;
}

} // namespace hoarbound::frost

#endif // HOARBOUND_FROST_PROGRESSION_HPP
