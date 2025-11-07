// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title SortUtils
 * @author BAOBAB Protocol
 * @notice Gas-optimized sorting algorithms for DeFi order matching and price-time priority
 * @dev Provides multiple sorting algorithms optimized for different use cases and data sizes
 * @dev Essential for order book operations, risk management, and portfolio optimization
 */
library SortUtils {
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    /// @dev Reverts when array is empty
    error EmptyArray();
    
    /// @dev Reverts when arrays have mismatched lengths
    error ArrayLengthMismatch();

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // QUICKSORT (Optimal for general-purpose sorting)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sort array using quicksort algorithm
     * @param arr Array to sort
     * @param ascending Whether to sort in ascending order
     * @return sorted Sorted array
     * @dev O(n log n) average case, O(n²) worst case
     */
    function quickSort(
        uint256[] memory arr,
        bool ascending
    ) internal pure returns (uint256[] memory sorted) {
        if (arr.length == 0) revert EmptyArray();
        
        sorted = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            sorted[i] = arr[i];
        }
        
        _quickSort(sorted, 0, int256(sorted.length) - 1, ascending);
    }

    /**
     * @notice Sort array with custom comparator using quicksort
     * @param arr Array to sort
     * @param comparator Custom comparison function
     * @return sorted Sorted array
     */
    function quickSortWithComparator(
        uint256[] memory arr,
        function(uint256, uint256) pure returns (bool) comparator
    ) internal pure returns (uint256[] memory sorted) {
        if (arr.length == 0) revert EmptyArray();
        
        sorted = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            sorted[i] = arr[i];
        }
        
        _quickSortWithComparator(sorted, 0, int256(sorted.length) - 1, comparator);
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // INSERTION SORT (Optimal for small arrays)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sort array using insertion sort
     * @param arr Array to sort
     * @param ascending Whether to sort in ascending order
     * @return sorted Sorted array
     * @dev O(n²) but very efficient for small arrays (<20 elements)
     */
    function insertionSort(
        uint256[] memory arr,
        bool ascending
    ) internal pure returns (uint256[] memory sorted) {
        if (arr.length == 0) revert EmptyArray();
        
        sorted = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            sorted[i] = arr[i];
        }
        
        for (uint256 i = 1; i < sorted.length; i++) {
            uint256 key = sorted[i];
            uint256 j = i;
            
            if (ascending) {
                while (j > 0 && sorted[j - 1] > key) {
                    sorted[j] = sorted[j - 1];
                    j--;
                }
            } else {
                while (j > 0 && sorted[j - 1] < key) {
                    sorted[j] = sorted[j - 1];
                    j--;
                }
            }
            sorted[j] = key;
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // ORDER BOOK SPECIFIC SORTING (Price-Time Priority)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sort orders by price-time priority (for bids: highest price, earliest time first)
     * @param orderIds Array of order IDs
     * @param prices Corresponding order prices
     * @param timestamps Corresponding order timestamps
     * @param isBid Whether sorting bid orders (true) or ask orders (false)
     * @return sortedOrderIds Order IDs sorted by price-time priority
     * @dev For bids: descending price, ascending timestamp
     * @dev For asks: ascending price, ascending timestamp
     */
    function sortByPriceTimePriority(
        uint256[] memory orderIds,
        uint256[] memory prices,
        uint256[] memory timestamps,
        bool isBid
    ) internal pure returns (uint256[] memory sortedOrderIds) {
        if (orderIds.length != prices.length || orderIds.length != timestamps.length) {
            revert ArrayLengthMismatch();
        }
        if (orderIds.length == 0) return orderIds;
        
        // Create array of indices to sort
        uint256[] memory indices = new uint256[](orderIds.length);
        for (uint256 i = 0; i < indices.length; i++) {
            indices[i] = i;
        }
        
        // Sort indices based on price-time priority
        _quickSortIndices(indices, prices, timestamps, isBid);
        
        // Build sorted order IDs from sorted indices
        sortedOrderIds = new uint256[](orderIds.length);
        for (uint256 i = 0; i < indices.length; i++) {
            sortedOrderIds[i] = orderIds[indices[i]];
        }
    }

    /**
     * @notice Sort by multiple criteria (primary and secondary sort)
     * @param arr Array to sort
     * @param primaryValues Primary sort values
     * @param secondaryValues Secondary sort values
     * @param primaryDescending Whether primary sort is descending
     * @param secondaryDescending Whether secondary sort is descending
     * @return sorted Sorted array
     */
    function sortByMultipleCriteria(
        uint256[] memory arr,
        uint256[] memory primaryValues,
        uint256[] memory secondaryValues,
        bool primaryDescending,
        bool secondaryDescending
    ) internal pure returns (uint256[] memory sorted) {
        if (arr.length != primaryValues.length || arr.length != secondaryValues.length) {
            revert ArrayLengthMismatch();
        }
        if (arr.length == 0) return arr;
        
        uint256[] memory indices = new uint256[](arr.length);
        for (uint256 i = 0; i < indices.length; i++) {
            indices[i] = i;
        }
        
        _quickSortMultiCriteria(indices, primaryValues, secondaryValues, primaryDescending, secondaryDescending);
        
        sorted = new uint256[](arr.length);
        for (uint256 i = 0; i < indices.length; i++) {
            sorted[i] = arr[indices[i]];
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // MERGE SORT (Stable, predictable gas cost)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sort array using merge sort (stable algorithm)
     * @param arr Array to sort
     * @param ascending Whether to sort in ascending order
     * @return sorted Sorted array
     * @dev O(n log n) guaranteed, stable sort
     */
    function mergeSort(
        uint256[] memory arr,
        bool ascending
    ) internal pure returns (uint256[] memory sorted) {
        if (arr.length == 0) revert EmptyArray();
        
        sorted = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            sorted[i] = arr[i];
        }
        
        if (sorted.length > 1) {
            _mergeSort(sorted, 0, sorted.length - 1, ascending);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // HEAP SORT (Optimal for large arrays)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Sort array using heap sort
     * @param arr Array to sort
     * @param ascending Whether to sort in ascending order
     * @return sorted Sorted array
     * @dev O(n log n) guaranteed, in-place
     */
    function heapSort(
        uint256[] memory arr,
        bool ascending
    ) internal pure returns (uint256[] memory sorted) {
        if (arr.length == 0) revert EmptyArray();
        
        sorted = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            sorted[i] = arr[i];
        }
        
        int256 n = int256(sorted.length);
        
        // Build heap
        for (int256 i = n / 2 - 1; i >= 0; i--) {
            _heapify(sorted, n, i, ascending);
        }
        
        // Extract elements from heap
        for (int256 i = n - 1; i > 0; i--) {
            // Move current root to end
            (sorted[0], sorted[uint256(i)]) = (sorted[uint256(i)], sorted[0]);
            _heapify(sorted, i, 0, ascending);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // SELECTION ALGORITHMS (Partial sorting)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Find the k-th smallest element using quickselect
     * @param arr Array to search
     * @param k K-th smallest element to find (0-indexed)
     * @return kthSmallest The k-th smallest element
     */
    function quickSelect(
        uint256[] memory arr,
        uint256 k
    ) internal pure returns (uint256 kthSmallest) {
        if (arr.length == 0) revert EmptyArray();
        if (k >= arr.length) revert IndexOutOfBounds();
        
        uint256[] memory copy = new uint256[](arr.length);
        for (uint256 i = 0; i < arr.length; i++) {
            copy[i] = arr[i];
        }
        
        return _quickSelect(copy, 0, int256(copy.length) - 1, int256(k));
    }

    /**
     * @notice Find top k elements (partial sort)
     * @param arr Array to search
     * @param k Number of top elements to find
     * @param descending Whether to get largest (true) or smallest (false)
     * @return topK Array of top k elements
     */
    function topK(
        uint256[] memory arr,
        uint256 k,
        bool descending
    ) internal pure returns (uint256[] memory topK) {
        if (arr.length == 0) revert EmptyArray();
        if (k == 0) return new uint256[](0);
        
        k = k > arr.length ? arr.length : k;
        
        if (descending) {
            // For largest k elements, find (n-k)th smallest and take larger ones
            uint256 threshold = quickSelect(arr, arr.length - k);
            return _filterGreaterOrEqual(arr, threshold);
        } else {
            // For smallest k elements, find k-th smallest and take smaller ones
            uint256 threshold = quickSelect(arr, k - 1);
            return _filterLessOrEqual(arr, threshold);
        }
    }

    /**
     * @notice Find median of array
     * @param arr Array to find median of
     * @return median Median value
     */
    function median(uint256[] memory arr) internal pure returns (uint256) {
        if (arr.length == 0) revert EmptyArray();
        
        if (arr.length % 2 == 1) {
            // Odd length: return middle element
            return quickSelect(arr, arr.length / 2);
        } else {
            // Even length: return average of two middle elements
            uint256 mid1 = quickSelect(arr, arr.length / 2 - 1);
            uint256 mid2 = quickSelect(arr, arr.length / 2);
            return (mid1 + mid2) / 2;
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // UTILITY FUNCTIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /**
     * @notice Check if array is sorted
     * @param arr Array to check
     * @param ascending Whether to check ascending order
     * @return isSorted True if array is sorted
     */
    function isSorted(
        uint256[] memory arr,
        bool ascending
    ) internal pure returns (bool) {
        if (arr.length <= 1) return true;
        
        for (uint256 i = 1; i < arr.length; i++) {
            if (ascending) {
                if (arr[i] < arr[i - 1]) return false;
            } else {
                if (arr[i] > arr[i - 1]) return false;
            }
        }
        return true;
    }

    /**
     * @notice Reverse array in-place
     * @param arr Array to reverse
     */
    function reverse(uint256[] memory arr) internal pure {
        uint256 left = 0;
        uint256 right = arr.length - 1;
        
        while (left < right) {
            (arr[left], arr[right]) = (arr[right], arr[left]);
            left++;
            right--;
        }
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // PRIVATE IMPLEMENTATIONS
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════

    /// @dev QuickSort implementation
    function _quickSort(
        uint256[] memory arr,
        int256 left,
        int256 right,
        bool ascending
    ) private pure {
        if (left < right) {
            int256 pi = _partition(arr, left, right, ascending);
            _quickSort(arr, left, pi - 1, ascending);
            _quickSort(arr, pi + 1, right, ascending);
        }
    }

    function _partition(
        uint256[] memory arr,
        int256 left,
        int256 right,
        bool ascending
    ) private pure returns (int256) {
        uint256 pivot = arr[uint256(right)];
        int256 i = left - 1;
        
        for (int256 j = left; j <= right - 1; j++) {
            bool condition = ascending ? arr[uint256(j)] <= pivot : arr[uint256(j)] >= pivot;
            if (condition) {
                i++;
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
            }
        }
        (arr[uint256(i + 1)], arr[uint256(right)]) = (arr[uint256(right)], arr[uint256(i + 1)]);
        return i + 1;
    }

    /// @dev QuickSort with custom comparator
    function _quickSortWithComparator(
        uint256[] memory arr,
        int256 left,
        int256 right,
        function(uint256, uint256) pure returns (bool) comparator
    ) private pure {
        if (left < right) {
            int256 pi = _partitionWithComparator(arr, left, right, comparator);
            _quickSortWithComparator(arr, left, pi - 1, comparator);
            _quickSortWithComparator(arr, pi + 1, right, comparator);
        }
    }

    function _partitionWithComparator(
        uint256[] memory arr,
        int256 left,
        int256 right,
        function(uint256, uint256) pure returns (bool) comparator
    ) private pure returns (int256) {
        uint256 pivot = arr[uint256(right)];
        int256 i = left - 1;
        
        for (int256 j = left; j <= right - 1; j++) {
            if (comparator(arr[uint256(j)], pivot)) {
                i++;
                (arr[uint256(i)], arr[uint256(j)]) = (arr[uint256(j)], arr[uint256(i)]);
            }
        }
        (arr[uint256(i + 1)], arr[uint256(right)]) = (arr[uint256(right)], arr[uint256(i + 1)]);
        return i + 1;
    }

    /// @dev Price-time priority sorting
    function _quickSortIndices(
        uint256[] memory indices,
        uint256[] memory prices,
        uint256[] memory timestamps,
        bool isBid
    ) private pure {
        _quickSortIndicesRecursive(indices, prices, timestamps, 0, int256(indices.length) - 1, isBid);
    }

    function _quickSortIndicesRecursive(
        uint256[] memory indices,
        uint256[] memory prices,
        uint256[] memory timestamps,
        int256 left,
        int256 right,
        bool isBid
    ) private pure {
        if (left < right) {
            int256 pi = _partitionIndices(indices, prices, timestamps, left, right, isBid);
            _quickSortIndicesRecursive(indices, prices, timestamps, left, pi - 1, isBid);
            _quickSortIndicesRecursive(indices, prices, timestamps, pi + 1, right, isBid);
        }
    }

    function _partitionIndices(
        uint256[] memory indices,
        uint256[] memory prices,
        uint256[] memory timestamps,
        int256 left,
        int256 right,
        bool isBid
    ) private pure returns (int256) {
        uint256 pivotIndex = indices[uint256(right)];
        int256 i = left - 1;
        
        for (int256 j = left; j <= right - 1; j++) {
            uint256 currentIndex = indices[uint256(j)];
            if (_comparePriceTime(currentIndex, pivotIndex, prices, timestamps, isBid)) {
                i++;
                (indices[uint256(i)], indices[uint256(j)]) = (indices[uint256(j)], indices[uint256(i)]);
            }
        }
        (indices[uint256(i + 1)], indices[uint256(right)]) = (indices[uint256(right)], indices[uint256(i + 1)]);
        return i + 1;
    }

    function _comparePriceTime(
        uint256 indexA,
        uint256 indexB,
        uint256[] memory prices,
        uint256[] memory timestamps,
        bool isBid
    ) private pure returns (bool) {
        if (prices[indexA] != prices[indexB]) {
            return isBid ? prices[indexA] > prices[indexB] : prices[indexA] < prices[indexB];
        }
        // Same price, earlier timestamp has priority
        return timestamps[indexA] < timestamps[indexB];
    }

    /// @dev Multi-criteria sorting
    function _quickSortMultiCriteria(
        uint256[] memory indices,
        uint256[] memory primary,
        uint256[] memory secondary,
        bool primaryDescending,
        bool secondaryDescending
    ) private pure {
        _quickSortMultiCriteriaRecursive(indices, primary, secondary, 0, int256(indices.length) - 1, primaryDescending, secondaryDescending);
    }

    function _quickSortMultiCriteriaRecursive(
        uint256[] memory indices,
        uint256[] memory primary,
        uint256[] memory secondary,
        int256 left,
        int256 right,
        bool primaryDescending,
        bool secondaryDescending
    ) private pure {
        if (left < right) {
            int256 pi = _partitionMultiCriteria(indices, primary, secondary, left, right, primaryDescending, secondaryDescending);
            _quickSortMultiCriteriaRecursive(indices, primary, secondary, left, pi - 1, primaryDescending, secondaryDescending);
            _quickSortMultiCriteriaRecursive(indices, primary, secondary, pi + 1, right, primaryDescending, secondaryDescending);
        }
    }

    function _partitionMultiCriteria(
        uint256[] memory indices,
        uint256[] memory primary,
        uint256[] memory secondary,
        int256 left,
        int256 right,
        bool primaryDescending,
        bool secondaryDescending
    ) private pure returns (int256) {
        uint256 pivotIndex = indices[uint256(right)];
        int256 i = left - 1;
        
        for (int256 j = left; j <= right - 1; j++) {
            uint256 currentIndex = indices[uint256(j)];
            if (_compareMultiCriteria(currentIndex, pivotIndex, primary, secondary, primaryDescending, secondaryDescending)) {
                i++;
                (indices[uint256(i)], indices[uint256(j)]) = (indices[uint256(j)], indices[uint256(i)]);
            }
        }
        (indices[uint256(i + 1)], indices[uint256(right)]) = (indices[uint256(right)], indices[uint256(i + 1)]);
        return i + 1;
    }

    function _compareMultiCriteria(
        uint256 indexA,
        uint256 indexB,
        uint256[] memory primary,
        uint256[] memory secondary,
        bool primaryDescending,
        bool secondaryDescending
    ) private pure returns (bool) {
        if (primary[indexA] != primary[indexB]) {
            return primaryDescending ? primary[indexA] > primary[indexB] : primary[indexA] < primary[indexB];
        }
        // Same primary value, use secondary
        return secondaryDescending ? secondary[indexA] > secondary[indexB] : secondary[indexA] < secondary[indexB];
    }

    /// @dev MergeSort implementation
    function _mergeSort(
        uint256[] memory arr,
        uint256 left,
        uint256 right,
        bool ascending
    ) private pure {
        if (left < right) {
            uint256 mid = left + (right - left) / 2;
            _mergeSort(arr, left, mid, ascending);
            _mergeSort(arr, mid + 1, right, ascending);
            _merge(arr, left, mid, right, ascending);
        }
    }

    function _merge(
        uint256[] memory arr,
        uint256 left,
        uint256 mid,
        uint256 right,
        bool ascending
    ) private pure {
        uint256 n1 = mid - left + 1;
        uint256 n2 = right - mid;
        
        uint256[] memory leftArr = new uint256[](n1);
        uint256[] memory rightArr = new uint256[](n2);
        
        for (uint256 i = 0; i < n1; i++) leftArr[i] = arr[left + i];
        for (uint256 j = 0; j < n2; j++) rightArr[j] = arr[mid + 1 + j];
        
        uint256 i = 0;
        uint256 j = 0;
        uint256 k = left;
        
        while (i < n1 && j < n2) {
            bool condition = ascending ? leftArr[i] <= rightArr[j] : leftArr[i] >= rightArr[j];
            if (condition) {
                arr[k] = leftArr[i];
                i++;
            } else {
                arr[k] = rightArr[j];
                j++;
            }
            k++;
        }
        
        while (i < n1) {
            arr[k] = leftArr[i];
            i++;
            k++;
        }
        
        while (j < n2) {
            arr[k] = rightArr[j];
            j++;
            k++;
        }
    }

    /// @dev HeapSort implementation
    function _heapify(
        uint256[] memory arr,
        int256 n,
        int256 i,
        bool ascending
    ) private pure {
        int256 extreme = i; // Initialize extreme as root
        int256 left = 2 * i + 1;
        int256 right = 2 * i + 2;
        
        // If left child is more extreme than root
        if (left < n) {
            bool leftCondition = ascending ? 
                arr[uint256(left)] > arr[uint256(extreme)] : 
                arr[uint256(left)] < arr[uint256(extreme)];
            if (leftCondition) extreme = left;
        }
        
        // If right child is more extreme than current extreme
        if (right < n) {
            bool rightCondition = ascending ? 
                arr[uint256(right)] > arr[uint256(extreme)] : 
                arr[uint256(right)] < arr[uint256(extreme)];
            if (rightCondition) extreme = right;
        }
        
        // If extreme is not root
        if (extreme != i) {
            (arr[uint256(i)], arr[uint256(extreme)]) = (arr[uint256(extreme)], arr[uint256(i)]);
            _heapify(arr, n, extreme, ascending);
        }
    }

    /// @dev QuickSelect implementation
    function _quickSelect(
        uint256[] memory arr,
        int256 left,
        int256 right,
        int256 k
    ) private pure returns (uint256) {
        if (left == right) return arr[uint256(left)];
        
        int256 pivotIndex = _partition(arr, left, right, true);
        
        if (k == pivotIndex) {
            return arr[uint256(k)];
        } else if (k < pivotIndex) {
            return _quickSelect(arr, left, pivotIndex - 1, k);
        } else {
            return _quickSelect(arr, pivotIndex + 1, right, k);
        }
    }

    /// @dev Filter helpers for topK
    function _filterGreaterOrEqual(
        uint256[] memory arr,
        uint256 threshold
    ) private pure returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] >= threshold) count++;
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] >= threshold) {
                result[index] = arr[i];
                index++;
            }
        }
        return result;
    }

    function _filterLessOrEqual(
        uint256[] memory arr,
        uint256 threshold
    ) private pure returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] <= threshold) count++;
        }
        
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < arr.length; i++) {
            if (arr[i] <= threshold) {
                result[index] = arr[i];
                index++;
            }
        }
        return result;
    }

    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    // CUSTOM ERRORS (Placeholder for compilation)
    // ══════════════════════════════════════════════════════════════════════════════════════════════════════════════════
    
    error IndexOutOfBounds();
}