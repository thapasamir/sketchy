import test from 'node:test'
import assert from 'node:assert/strict'
import { chosenCategories, tapCategory } from './categories.js'

const EVERYTHING = ['A', 'B', 'C']

test('tapping a category while everything is chosen means just that one', () => {
  assert.deepEqual(tapCategory('all', EVERYTHING, 'B'), ['B'])
})

test('after that, tapping adds and removes', () => {
  assert.deepEqual(tapCategory(['B'], EVERYTHING, 'A'), ['B', 'A'])
  assert.deepEqual(tapCategory(['B', 'A'], EVERYTHING, 'B'), ['A'])
})

test('the last one cannot be removed', () => {
  assert.equal(tapCategory(['B'], EVERYTHING, 'B'), null)
})

test('choosing them all again is the same as all', () => {
  assert.equal(tapCategory(['A', 'B'], EVERYTHING, 'C'), 'all')
})

test('as a list', () => {
  assert.deepEqual(chosenCategories('all', EVERYTHING), EVERYTHING)
  assert.deepEqual(chosenCategories(['B'], EVERYTHING), ['B'])
})
