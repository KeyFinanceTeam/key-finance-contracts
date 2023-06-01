// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

library SortedArrays {
    struct SortedArray {
        uint256[] array;
        mapping(uint256 => bool) exist;
        bool ascending;
    }

    function initialize(SortedArray storage _sortedArray, bool _ascending) internal {
        _sortedArray.ascending = _ascending;
    }

    function insertIfNotExist(SortedArray storage _sortedArray, uint256 value) internal {
        if (_sortedArray.exist[value]) return;

        if (_sortedArray.array.length == 0) {
            _sortedArray.array.push(value);
            _sortedArray.exist[value] = true;
        } else {
            uint256 i = 0;
            if (_sortedArray.ascending) {
                while (i < _sortedArray.array.length && _sortedArray.array[i] < value) {
                    i++;
                }
            } else {
                while (i < _sortedArray.array.length && _sortedArray.array[i] > value) {
                    i++;
                }
            }
            // Expand the array by one element
            _sortedArray.array.push(_sortedArray.array[_sortedArray.array.length - 1]);

            // Shift elements from the end of the array to the insertion point
            if (_sortedArray.array.length > 2) {
                for (uint j = _sortedArray.array.length - 2; j > i; j--) {
                    _sortedArray.array[j] = _sortedArray.array[j - 1];
                }
            }

            // Insert the new value
            _sortedArray.array[i] = value;
            _sortedArray.exist[value] = true;
        }
    }

    function removeIfExist(SortedArray storage _sortedArray, uint value) internal {
        if (!_sortedArray.exist[value]) return;
        for (uint i = 0; i < _sortedArray.array.length; i++) {
            if (_sortedArray.array[i] == value) {
                // Shift all elements to the left
                for (uint j = i; j < _sortedArray.array.length - 1; j++) {
                    _sortedArray.array[j] = _sortedArray.array[j + 1];
                }

                // Remove the last element
                _sortedArray.array.pop();
                _sortedArray.exist[value] = false;
                break;
            }
        }
    }
}
