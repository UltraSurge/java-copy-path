package com.example.demo;

import java.util.List;
import java.util.ArrayList;

/**
 * 测试类 - 演示内部类和泛型方法支持
 */
public class DemoService {

    private List<String> items = new ArrayList<>();

    // 泛型方法示例
    public <T> T process(T item) {
        System.out.println("Processing: " + item);
        return item;
    }

    // 带参数的泛型方法
    public <T extends Comparable<T>> T findMax(List<T> items) {
        if (items.isEmpty()) {
            return null;
        }
        T max = items.get(0);
        for (T item : items) {
            if (item.compareTo(max) > 0) {
                max = item;
            }
        }
        return max;
    }

    // 多个泛型参数
    public <K, V> void put(K key, V value) {
        System.out.println("Key: " + key + ", Value: " + value);
    }

    // 普通方法
    public void addItem(String item) {
        items.add(item);
    }

    /**
     * 内部类示例
     */
    public class InnerProcessor {

        private String name;

        public InnerProcessor(String name) {
            this.name = name;
        }

        // 内部类的方法
        public void processData() {
            System.out.println("Processing with: " + name);
        }

        // 内部类的泛型方法
        public <T> List<T> transform(List<T> input) {
            return new ArrayList<>(input);
        }

        /**
         * 嵌套内部类示例
         */
        public class NestedProcessor {

            public void execute() {
                System.out.println("Nested execution");
            }

            // 嵌套内部类的泛型方法
            public <E> E getFirst(List<E> list) {
                return list.isEmpty() ? null : list.get(0);
            }
        }
    }

    /**
     * 静态内部类示例
     */
    public static class StaticHelper {

        public static <T> boolean isEmpty(List<T> list) {
            return list == null || list.isEmpty();
        }

        public static void log(String message) {
            System.out.println("[LOG] " + message);
        }
    }
}
