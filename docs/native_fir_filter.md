To re-implement the `fir1` function from Octave in Python, we can use the `scipy.signal` library, which provides similar functionality for designing FIR filters. The `scipy.signal.firwin` function is particularly useful for creating linear phase FIR filters with a specified frequency response.

Here's how you can implement the `fir1` function in Python:

```python
import numpy as np
from scipy.signal import firwin

def fir1(n, w, fs=None, type='low', window='hamming', scale=True):
    """
    Produce an order n FIR filter with the given frequency cutoff w,
    returning the n+1 filter coefficients in b. If w is a scalar, it specifies
    the frequency cutoff for a lowpass or highpass filter. If w is a two-element
    vector, the two values specify the edges of a bandpass or bandstop filter.

    Parameters:
        n (int): The order of the FIR filter.
        w (float or array-like): A scalar or a 2-element list specifying the frequency cutoff(s).
                               Frequencies must be normalized between 0 and fs/2, where fs is the sampling rate.
        fs (float, optional): Sampling frequency. If specified, frequencies in w are relative to this value.
                              Defaults to None, meaning that values in w should be normalized between 0 and 1.
        type (str): The filter type: 'low', 'high', 'bandpass', or 'bandstop'.
                    Defaults to 'low'.
        window (str or array-like): Window function applied to the ideal impulse response.
                                    Can also be a tuple where the first element is a string representing
                                    the window and the second element is a parameter for the window.
                                    Defaults to 'hamming'.
        scale (bool): If True, the filter coefficients are normalized so that the gain at the center of
                      the passband is 1. Defaults to True.

    Returns:
        b (array): The n+1 filter coefficients representing the FIR filter.
    """

    # Normalize frequencies if fs is provided
    if fs is not None:
        w = np.asarray(w) / (fs / 2)

    # Check for valid type
    valid_types = ['low', 'high', 'bandpass', 'bandstop']
    if type not in valid_types:
        raise ValueError(f"Filter type must be one of {valid_types}")

    # Define the window parameter if it's a string or a tuple
    window_param = None
    if isinstance(window, (tuple, list)):
        window_name, window_param = window[0], window[1:]
        window = window_name

    # Create filter coefficients using firwin
    b = firwin(numtaps=n+1, cutoff=w, fs=2, pass_zero=(type == 'low' or type == 'bandstop'),
               window=window if window_param is None else (window, *window_param), scale=scale)

    return b

# Example usage:
# Design a lowpass filter with order 40 and cutoff frequency of 300 Hz at a sampling rate of 1000 Hz
b = fir1(n=40, w=300, fs=1000, type='low')
print(b)
```

### Explanation:
- **Parameters**:
    - `n`: The order of the filter. This is the number of taps minus one.
    - `w`: Frequency cutoff(s) for the filter. If `fs` is provided, these frequencies should be in Hz; otherwise, they should be normalized between 0 and 1 (where 1 corresponds to the Nyquist frequency).
    - `fs`: The sampling frequency. If specified, it allows the function to accept cutoff frequencies in Hz.
    - `type`: Specifies the type of filter ('low', 'high', 'bandpass', or 'bandstop').
    - `window`: The windowing function applied to the ideal impulse response. It can be a string (e.g., 'hamming') or a tuple specifying additional parameters for certain windows.
    - `scale`: Whether to normalize the filter coefficients so that the gain at the center of the passband is 1.

- **firwin**: This function from `scipy.signal` generates the filter coefficients. It uses window functions and normalizes the frequency response based on the specified type and scale options.

This Python function mirrors the functionality of Octave's `fir1` while leveraging the capabilities of the SciPy library for signal processing.