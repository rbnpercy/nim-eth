#
#                   Waku
#              (c) Copyright 2019
#       Status Research & Development GmbH
#
#            Licensed under either of
#  Apache License, version 2.0, (LICENSE-APACHEv2)
#            MIT license (LICENSE-MIT)

import
  sequtils, tables, unittest, chronos, eth/[keys, p2p],
  eth/p2p/rlpx_protocols/waku_protocol, eth/p2p/peer_pool,
  ./p2p_test_helper

const
  safeTTL = 5'u32
  waitInterval = messageInterval + 150.milliseconds

# TODO: Just repeat all the test_shh_connect tests here that are applicable or
# have some commonly shared test code for both protocols.
suite "Waku connections":
  asyncTest "Waku connections":
    var
      n1 = setupTestNode(Waku)
      n2 = setupTestNode(Waku)
      n3 = setupTestNode(Waku)
      n4 = setupTestNode(Waku)

    var topics: seq[Topic]
    n1.protocolState(Waku).config.topics = some(topics)
    n2.protocolState(Waku).config.topics = some(topics)
    n3.protocolState(Waku).config.topics = none(seq[Topic])
    n4.protocolState(Waku).config.topics = none(seq[Topic])

    n1.startListening()
    n3.startListening()

    let
      p1 = await n2.rlpxConnect(newNode(initENode(n1.keys.pubKey, n1.address)))
      p2 = await n2.rlpxConnect(newNode(initENode(n3.keys.pubKey, n3.address)))
      p3 = await n4.rlpxConnect(newNode(initENode(n3.keys.pubKey, n3.address)))
    check:
      p1.isNil
      p2.isNil == false
      p3.isNil == false

  asyncTest "Waku topic-interest":
    var
      wakuTopicNode = setupTestNode(Waku)
      wakuNode = setupTestNode(Waku)

    let
      topic1 = [byte 0xDA, 0xDA, 0xDA, 0xAA]
      topic2 = [byte 0xD0, 0xD0, 0xD0, 0x00]
      wrongTopic = [byte 0x4B, 0x1D, 0x4B, 0x1D]

    wakuTopicNode.protocolState(Waku).config.topics = some(@[topic1, topic2])

    wakuNode.startListening()
    await wakuTopicNode.peerPool.connectToNode(newNode(
      initENode(wakuNode.keys.pubKey, wakuNode.address)))

    let payload = repeat(byte 0, 10)
    check:
      wakuNode.postMessage(ttl = safeTTL, topic = topic1, payload = payload)
      wakuNode.postMessage(ttl = safeTTL, topic = topic2, payload = payload)
      wakuNode.postMessage(ttl = safeTTL, topic = wrongTopic, payload = payload)
      wakuNode.protocolState(Waku).queue.items.len == 3
    await sleepAsync(waitInterval)
    check:
      wakuTopicNode.protocolState(Waku).queue.items.len == 2

  asyncTest "Waku topic-interest versus bloom filter":
    var
      wakuTopicNode = setupTestNode(Waku)
      wakuNode = setupTestNode(Waku)

    let
      topic1 = [byte 0xDA, 0xDA, 0xDA, 0xAA]
      topic2 = [byte 0xD0, 0xD0, 0xD0, 0x00]
      bloomTopic = [byte 0x4B, 0x1D, 0x4B, 0x1D]

    # It was checked that the topics don't trigger false positives on the bloom.
    wakuTopicNode.protocolState(Waku).config.topics = some(@[topic1, topic2])
    wakuTopicNode.protocolState(Waku).config.bloom = toBloom([bloomTopic])

    wakuNode.startListening()
    await wakuTopicNode.peerPool.connectToNode(newNode(
      initENode(wakuNode.keys.pubKey, wakuNode.address)))

    let payload = repeat(byte 0, 10)
    check:
      wakuNode.postMessage(ttl = safeTTL, topic = topic1, payload = payload)
      wakuNode.postMessage(ttl = safeTTL, topic = topic2, payload = payload)
      wakuNode.postMessage(ttl = safeTTL, topic = bloomTopic, payload = payload)
      wakuNode.protocolState(Waku).queue.items.len == 3
    await sleepAsync(waitInterval)
    check:
      wakuTopicNode.protocolState(Waku).queue.items.len == 2

  asyncTest "Light node posting":
    var ln = setupTestNode(Waku)
    ln.setLightNode(true)
    var fn = setupTestNode(Waku)
    fn.startListening()
    await ln.peerPool.connectToNode(newNode(initENode(fn.keys.pubKey,
                                                      fn.address)))

    let topic = [byte 0, 0, 0, 0]

    check:
      ln.peerPool.connectedNodes.len() == 1
      # normal post
      ln.postMessage(ttl = safeTTL, topic = topic,
                      payload = repeat(byte 0, 10)) == true
      ln.protocolState(Waku).queue.items.len == 1
      # TODO: add test on message relaying
