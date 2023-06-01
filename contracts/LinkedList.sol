// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

library LinkedList {
    struct Node {
        uint256 data;
        uint256 prev;
        uint256 next;
    }

    struct List {
        mapping(uint256 => Node) nodes;
        uint256 lastId;
        uint256 head;
        uint256 tail;
        uint256 size;
    }

    function insert(List storage list, uint256 data) internal returns (uint256) {
        list.lastId += 1;
        Node memory node = Node(data, list.tail, 0);
        list.nodes[list.lastId] = node;
        if(list.tail != 0) {
            list.nodes[list.tail].next = list.lastId;
        }
        list.tail = list.lastId;
        if(list.head == 0) {
            list.head = list.tail;
        }
        list.size++;
        return list.lastId;
    }

    function remove(List storage list, uint256 id) internal {
        require(id <= list.lastId, "Index out of bounds");
        require(id != 0, "Invalid index");

        if(list.nodes[id].next != 0) {
            list.nodes[list.nodes[id].next].prev = list.nodes[id].prev;
        }
        if(list.nodes[id].prev != 0) {
            list.nodes[list.nodes[id].prev].next = list.nodes[id].next;
        }
        if (list.nodes[id].next != 0 || list.nodes[id].prev != 0 || (list.head == id && list.tail == id)) list.size--;
        if(list.head == id) {
            list.head = list.nodes[id].next;
        }
        if(list.tail == id) {
            list.tail = list.nodes[id].prev;
        }
        delete list.nodes[id];
    }

    function get(List storage list, uint256 id) internal view returns (uint256 data, uint256 prev, uint256 next) {
        require(id <= list.lastId, "Index out of bounds");
        require(id != 0, "Invalid index");
        require(list.nodes[id].next != 0 || list.nodes[id].prev != 0 || (list.head == id && list.tail == id), "Invalid node");
        Node memory node = list.nodes[id];
        return (node.data, node.prev, node.next);
    }

    function removeFirst(List storage list) internal {
        require(list.head != 0, "List is empty");
        remove(list, list.head);
    }
}