// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title ArrayUtils
 * @author BAOBAB Protocol
 * @notice Gas-optimized array manipulation utilities for DeFi applications
 * @dev Provides efficient array operations with comprehensive error handling
 * @dev Optimized for trading data, position management, and order book operations
 */
library ArrayUtils {
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    /// @dev Reverts when array index is out of bounds
    error IndexOutOfBounds();
    
    /// @dev Reverts when array is empty
    error EmptyArray();
    
    /// @dev Reverts when arrays have mismatched lengths
    error ArrayLengthMismatch();
    
    /// @dev Reverts when element not found in array
    error ElementNotFound();

    /// @dev Reverts when element is wrong
    error InvalidInput();

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ARRAY MANIPULATION OPERATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Insert element at specific index
     * @param array Array to insert into
     * @param index Index to insert at
     * @param element Element to insert
     * @return newArray New array with element inserted
     * @dev Reverts if index is out of bounds
     */
    function insert(
        uint256[] memory array,
        uint256 index,
        uint256 element
    ) internal pure returns (uint256[] memory newArray) {
        if (index > array.length) revert IndexOutOfBounds();
        
        newArray = new uint256[](array.length + 1);
        
        // Copy elements before index
        for (uint256 i = 0; i < index; i++) {
            newArray[i] = array[i];
        }
        
        // Insert new element
        newArray[index] = element;
        
        // Copy elements after index
        for (uint256 i = index; i < array.length; i++) {
            newArray[i + 1] = array[i];
        }
    }

    /**
     * @notice Remove element at specific index
     * @param array Array to remove from
     * @param index Index to remove at
     * @return newArray New array with element removed
     * @dev Reverts if index is out of bounds
     */
    function removeAt(
        uint256[] memory array,
        uint256 index
    ) internal pure returns (uint256[] memory newArray) {
        if (array.length == 0) revert EmptyArray();
        if (index >= array.length) revert IndexOutOfBounds();
        
        newArray = new uint256[](array.length - 1);
        
        // Copy elements before index
        for (uint256 i = 0; i < index; i++) {
            newArray[i] = array[i];
        }
        
        // Copy elements after index
        for (uint256 i = index + 1; i < array.length; i++) {
            newArray[i - 1] = array[i];
        }
    }

    /**
     * @notice Remove first occurrence of element
     * @param array Array to remove from
     * @param element Element to remove
     * @return newArray New array with element removed
     * @dev Reverts if element not found
     */
    function removeElement(
        uint256[] memory array,
        uint256 element
    ) internal pure returns (uint256[] memory newArray) {
        int256 index = indexOf(array, element);
        if (index == -1) revert ElementNotFound();
        
        return removeAt(array, uint256(index));
    }

    /**
     * @notice Append element to array
     * @param array Array to append to
     * @param element Element to append
     * @return newArray New array with element appended
     */
    function append(
        uint256[] memory array,
        uint256 element
    ) internal pure returns (uint256[] memory newArray) {
        newArray = new uint256[](array.length + 1);
        
        for (uint256 i = 0; i < array.length; i++) {
            newArray[i] = array[i];
        }
        
        newArray[array.length] = element;
    }

    /**
     * @notice Prepend element to array
     * @param array Array to prepend to
     * @param element Element to prepend
     * @return newArray New array with element prepended
     */
    function prepend(
        uint256[] memory array,
        uint256 element
    ) internal pure returns (uint256[] memory newArray) {
        return insert(array, 0, element);
    }

    /**
     * @notice Concatenate two arrays
     * @param a First array
     * @param b Second array
     * @return newArray Concatenated array
     */
    function concat(
        uint256[] memory a,
        uint256[] memory b
    ) internal pure returns (uint256[] memory newArray) {
        newArray = new uint256[](a.length + b.length);
        
        for (uint256 i = 0; i < a.length; i++) {
            newArray[i] = a[i];
        }
        
        for (uint256 i = 0; i < b.length; i++) {
            newArray[a.length + i] = b[i];
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // SEARCH AND QUERY OPERATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Find index of element in array
     * @param array Array to search
     * @param element Element to find
     * @return index Index of element, or -1 if not found
     */
    function indexOf(
        uint256[] memory array,
        uint256 element
    ) internal pure returns (int256) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                return int256(i);
            }
        }
        return -1;
    }

    /**
     * @notice Check if array contains element
     * @param array Array to search
     * @param element Element to check
     * @return contains True if array contains element
     */
    function contains(
        uint256[] memory array,
        uint256 element
    ) internal pure returns (bool) {
        return indexOf(array, element) != -1;
    }

    /**
     * @notice Find all indices of element in array
     * @param array Array to search
     * @param element Element to find
     * @return indices Array of indices where element is found
     */
    function indicesOf(
        uint256[] memory array,
        uint256 element
    ) internal pure returns (uint256[] memory indices) {
        uint256 count = 0;
        
        // First pass: count occurrences
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                count++;
            }
        }
        
        // Second pass: record indices
        indices = new uint256[](count);
        uint256 currentIndex = 0;
        
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                indices[currentIndex] = i;
                currentIndex++;
            }
        }
    }

    /**
     * @notice Find minimum value in array
     * @param array Array to search
     * @return minValue Minimum value
     * @dev Reverts if array is empty
     */
    function min(uint256[] memory array) internal pure returns (uint256) {
        if (array.length == 0) revert EmptyArray();
        
        uint256 minValue = array[0];
        for (uint256 i = 1; i < array.length; i++) {
            if (array[i] < minValue) {
                minValue = array[i];
            }
        }
        return minValue;
    }

    /**
     * @notice Find maximum value in array
     * @param array Array to search
     * @return maxValue Maximum value
     * @dev Reverts if array is empty
     */
    function max(uint256[] memory array) internal pure returns (uint256) {
        if (array.length == 0) revert EmptyArray();
        
        uint256 maxValue = array[0];
        for (uint256 i = 1; i < array.length; i++) {
            if (array[i] > maxValue) {
                maxValue = array[i];
            }
        }
        return maxValue;
    }

    /**
     * @notice Calculate sum of array elements
     * @param array Array to sum
     * @return total Sum of all elements
     */
    function sum(uint256[] memory array) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < array.length; i++) {
            total += array[i];
        }
    }

    /**
     * @notice Calculate average of array elements
     * @param array Array to average
     * @return average Average value
     * @dev Reverts if array is empty
     */
    function average(uint256[] memory array) internal pure returns (uint256) {
        if (array.length == 0) revert EmptyArray();
        return sum(array) / array.length;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // SLICE AND SPLIT OPERATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Slice array from start to end index
     * @param array Array to slice
     * @param start Start index (inclusive)
     * @param end End index (exclusive)
     * @return slice Sliced array
     * @dev Reverts if indices are out of bounds
     */
    function slice(
        uint256[] memory array,
        uint256 start,
        uint256 end
    ) internal pure returns (uint256[] memory) {
        if (start > end || end > array.length) revert IndexOutOfBounds();
        
        uint256[] memory sliceArray = new uint256[](end - start);
        
        for (uint256 i = start; i < end; i++) {
            sliceArray[i - start] = array[i];
        }
        
        return sliceArray;
    }

    /**
     * @notice Get first n elements of array
     * @param array Array to slice
     * @param n Number of elements to take
     * @return firstN First n elements
     */
    function take(
        uint256[] memory array,
        uint256 n
    ) internal pure returns (uint256[] memory) {
        if (n > array.length) n = array.length;
        return slice(array, 0, n);
    }

    /**
     * @notice Get last n elements of array
     * @param array Array to slice
     * @param n Number of elements to take
     * @return lastN Last n elements
     */
    function takeLast(
        uint256[] memory array,
        uint256 n
    ) internal pure returns (uint256[] memory) {
        if (n > array.length) n = array.length;
        return slice(array, array.length - n, array.length);
    }

    /**
     * @notice Split array into chunks of specified size
     * @param array Array to split
     * @param chunkSize Size of each chunk
     * @return chunks Array of chunks
     */
    function chunk(
        uint256[] memory array,
        uint256 chunkSize
    ) internal pure returns (uint256[][] memory chunks) {
        if (chunkSize == 0) revert InvalidInput();
        
        uint256 numChunks = (array.length + chunkSize - 1) / chunkSize;
        chunks = new uint256[][](numChunks);
        
        for (uint256 i = 0; i < numChunks; i++) {
            uint256 start = i * chunkSize;
            uint256 end = start + chunkSize > array.length ? array.length : start + chunkSize;
            chunks[i] = slice(array, start, end);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // SET OPERATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Remove duplicate elements from array
     * @param array Array to deduplicate
     * @return uniqueArray Array with duplicates removed
     */
    function unique(uint256[] memory array) internal pure returns (uint256[] memory uniqueArray) {
        if (array.length == 0) return array;
        
        uint256[] memory temp = new uint256[](array.length);
        uint256 uniqueCount = 0;
        
        for (uint256 i = 0; i < array.length; i++) {
            if (!_contains(temp, array[i], uniqueCount)) {
                temp[uniqueCount] = array[i];
                uniqueCount++;
            }
        }
        
        uniqueArray = new uint256[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            uniqueArray[i] = temp[i];
        }
    }

    /**
     * @notice Get intersection of two arrays
     * @param a First array
     * @param b Second array
     * @return intersection Array of common elements
     */
    function intersections(
        uint256[] memory a,
        uint256[] memory b
    ) internal pure returns (uint256[] memory intersection) {
        uint256[] memory temp = new uint256[](a.length < b.length ? a.length : b.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < a.length; i++) {
            if (contains(b, a[i]) && !_contains(temp, a[i], count)) {
                temp[count] = a[i];
                count++;
            }
        }
        
        intersection = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            intersection[i] = temp[i];
        }
    }

    /**
     * @notice Get union of two arrays
     * @param a First array
     * @param b Second array
     * @return union Array of all unique elements from both arrays
     */
    function union(
        uint256[] memory a,
        uint256[] memory b
    ) internal pure returns (uint256[] memory) {
        return unique(concat(a, b));
    }

    /**
     * @notice Get difference between two arrays (a - b)
     * @param a First array
     * @param b Second array
     * @return difference Elements in a but not in b
     */
    function differences(
        uint256[] memory a,
        uint256[] memory b
    ) internal pure returns (uint256[] memory difference) {
        uint256[] memory temp = new uint256[](a.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < a.length; i++) {
            if (!contains(b, a[i])) {
                temp[count] = a[i];
                count++;
            }
        }
        
        difference = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            difference[i] = temp[i];
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // TRANSFORMATION OPERATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Reverse array elements
     * @param array Array to reverse
     * @return reversed Reversed array
     */
    function reverse(uint256[] memory array) internal pure returns (uint256[] memory reversed) {
        reversed = new uint256[](array.length);
        
        for (uint256 i = 0; i < array.length; i++) {
            reversed[i] = array[array.length - 1 - i];
        }
    }

    /**
     * @notice Map array elements using a function
     * @param array Array to map
     * @param func Mapping function
     * @return mapped Array with mapped elements
     */
    function map(
        uint256[] memory array,
        function(uint256) pure returns (uint256) func
    ) internal pure returns (uint256[] memory mapped) {
        mapped = new uint256[](array.length);
        
        for (uint256 i = 0; i < array.length; i++) {
            mapped[i] = func(array[i]);
        }
    }

    /**
     * @notice Filter array elements using a predicate
     * @param array Array to filter
     * @param predicate Filter function
     * @return filtered Array with filtered elements
     */
    function filter(
        uint256[] memory array,
        function(uint256) pure returns (bool) predicate
    ) internal pure returns (uint256[] memory filtered) {
        uint256[] memory temp = new uint256[](array.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < array.length; i++) {
            if (predicate(array[i])) {
                temp[count] = array[i];
                count++;
            }
        }
        
        filtered = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            filtered[i] = temp[i];
        }
    }

    /**
     * @notice Reduce array to single value using accumulator
     * @param array Array to reduce
     * @param initial Initial value
     * @param reducer Reduction function
     * @return result Reduced value
     */
    function reduce(
        uint256[] memory array,
        uint256 initial,
        function(uint256, uint256) pure returns (uint256) reducer
    ) internal pure returns (uint256 result) {
        result = initial;
        
        for (uint256 i = 0; i < array.length; i++) {
            result = reducer(result, array[i]);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // PRIVATE HELPER FUNCTIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @dev Check if array contains element (internal, with count)
     */
    function _contains(
        uint256[] memory array,
        uint256 element,
        uint256 count
    ) private pure returns (bool) {
        for (uint256 i = 0; i < count; i++) {
            if (array[i] == element) {
                return true;
            }
        }
        return false;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ADDRESS ARRAY OPERATIONS (Commonly used in DeFi)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Remove address from array
     * @param array Array of addresses
     * @param element Address to remove
     * @return newArray New array with address removed
     */
    function removeAddress(
        address[] memory array,
        address element
    ) internal pure returns (address[] memory newArray) {
        int256 index = indexOfAddress(array, element);
        if (index == -1) revert ElementNotFound();
        
        newArray = new address[](array.length - 1);
        
        for (uint256 i = 0; i < uint256(index); i++) {
            newArray[i] = array[i];
        }
        
        for (uint256 i = uint256(index) + 1; i < array.length; i++) {
            newArray[i - 1] = array[i];
        }
    }

    /**
     * @notice Find index of address in array
     * @param array Array of addresses
     * @param element Address to find
     * @return index Index of address, or -1 if not found
     */
    function indexOfAddress(
        address[] memory array,
        address element
    ) internal pure returns (int256) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                return int256(i);
            }
        }
        return -1;
    }

    /**
     * @notice Check if address array contains element
     * @param array Array of addresses
     * @param element Address to check
     * @return contains True if array contains address
     */
    function containsAddress(
        address[] memory array,
        address element
    ) internal pure returns (bool) {
        return indexOfAddress(array, element) != -1;
    }
}